# frozen_string_literal: true

require 'open3'
# RbConfig arrives with RubyGems, not with the interpreter: `ruby --disable-gems`
# raises NameError on it. The example at :587 calls `RbConfig.ruby` to re-invoke
# the current interpreter, so requiring it here is what makes that example
# independent of how the suite was launched.
require 'rbconfig'
require 'stringio'
require 'timeout'
require 'tmpdir'

# The harness is a program, not a library. Loading it into a module runs the
# definitions without the main block, and keeps its methods and constants off
# Object for the rest of the suite.
MermaidDiff = Module.new
load File.expand_path('../../scripts/mermaid_diff.rb', __dir__), MermaidDiff
CorpusVerdicts = Module.new
load File.expand_path('../../scripts/corpus_verdicts.rb', __dir__), CorpusVerdicts

# Every example that breaks `ps` puts a real broken `ps` on PATH, and every
# process tree uses real processes — a stub would only prove that the rescue
# matches what the stub was told to raise.
RSpec.describe MermaidDiff do
  subject(:harness) { Class.new { include MermaidDiff }.new }

  let(:corpus_harness) { Class.new { include CorpusVerdicts }.new }
  let(:spawned) { [] }

  # The harness reads the process table with `ps` and signals process groups.
  # Windows has neither, so the program cannot run there and there is nothing
  # here to check. Without this the whole windows-latest column went red while
  # every other platform passed.
  before { skip('the harness is POSIX-only') if Gem.win_platform? }

  after { spawned.each { |pid| kill_quietly(pid) } }

  describe 'classifying a verdict' do
    it 'maps every tool-result pair to its kind and agreement' do
      states = [
        [:accepts, :accepts],
        [:rejects, :rejects],
        [:rejects, :accepts],
        [:accepts, :rejects],
        [:accepts, :error],
        [:rejects, :error]
      ]

      actual = states.map do |sirena, mermaid|
        verdict = MermaidDiff::Verdict.new('source', sirena, mermaid)
        [verdict.kind, verdict.agree?]
      end

      expect(actual).to eq(
        [
          [:agree, true],
          [:agree, true],
          [:gap, false],
          [:over_acceptance, false],
          [:infrastructure, false],
          [:infrastructure, false]
        ]
      )
    end
  end

  # A broken `ps` costs the descendant list and nothing else. It used to cost
  # the group kill too: the exec failure raised straight out of kill_group and
  # left mmdc and its child running.
  describe 'the descendant sweep' do
    {
      'is not on PATH at all' => nil,
      'never answers' => "#!/bin/sh\nexec /bin/sleep 30 2>/dev/null\n",
      'prints bytes that are not UTF-8' => "#!/bin/sh\nprintf '\\377\\376 1 0\\n'\n"
    }.each do |trouble, script|
      it "kills the group anyway when ps #{trouble}" do
        stub_const('MermaidDiff::PS_TIMEOUT', 0.3)
        parent, _child = spawn_tree

        only('ps', script) { Timeout.timeout(guard) { harness.send(:kill_group, parent) } }

        expect(dies?(parent)).to be(true)
      end
    end

    it 'kills a descendant that sits in a process group of its own' do
      parent, child = spawn_tree

      Timeout.timeout(guard) { harness.send(:kill_group, parent) }

      expect(dies?(child)).to be(true)
    end

    it 'keeps malformed and nonpositive pids out of the descendant list' do
      pid = Process.pid
      table = "#!/bin/sh\nprintf '%s\\n' 'garbled #{pid}' '7garbled #{pid}' " \
              "'0 #{pid}' '-7 #{pid}' '8 #{pid}garbled' '9 0' '10 -7'\n"

      descendants = only('ps', table) { harness.send(:subtree_of, pid) }

      expect(descendants).to eq([])
    end

    # Giving up on a wedged `ps` is not enough. A descendant can inherit the
    # capture pipe's write end, so leaving it running keeps the read from EOF:
    # measured, the sweep returned in 0.30s and the reader waited 21.29s.
    it 'kills a ps that never answers rather than leave its pipe open' do
      stub_const('MermaidDiff::PS_TIMEOUT', 1)

      only('ps', wedge('20.17')) do
        Timeout.timeout(guard) { harness.send(:descendants_of, Process.pid) }
      end

      expect(gone?('20.17')).to be(true)
    end
  end

  # The deadline is not the only thing that can be true when cleanup runs.
  # Collecting descendants means waiting on `ps`, and mmdc can finish while
  # that happens.
  describe 'waiting out the deadline' do
    it 'keeps the status of a program that finished while ps was running' do
      stub_const('MermaidDiff::CASE_TIMEOUT', 0)
      pid = Process.spawn('/bin/sh', '-c', 'sleep 0.4; exit 7', pgroup: true)
      spawned << pid

      status = only('ps', slow_ps) { Timeout.timeout(guard) { harness.send(:wait_with_deadline, pid) } }

      expect(status.exitstatus).to eq(7)
    end

    # The complement: a program the deadline really did kill has no verdict,
    # and handing back its status would read as mermaid rejecting the source.
    it 'gives no status for a program the deadline killed' do
      stub_const('MermaidDiff::CASE_TIMEOUT', 0)
      pid = Process.spawn('/bin/sh', '-c', 'sleep 20.61', pgroup: true)
      spawned << pid

      status = Timeout.timeout(guard) { harness.send(:wait_with_deadline, pid) }

      expect(status).to be_nil
    end

    # A case that times out is cleaned up twice: the deadline reaps mmdc, and
    # then run_mmdc cleans up again because it came away with no status. The
    # second pass has nothing left to wait for, and it used to raise
    # Errno::ECHILD straight out of the harness on every case that timed out.
    it 'cleans up twice after a case that timed out without raising' do
      stub_const('MermaidDiff::CASE_TIMEOUT', 0.3)

      status, output = Dir.mktmpdir do |dir|
        prefix_path(fake_mmdc(dir, "#!/bin/sh\nexec /bin/sleep 26.43\n")) do
          Timeout.timeout(guard) do
            harness.send(:run_mmdc, File.join(dir, 'in.mmd'), File.join(dir, 'out.svg'))
          end
        end
      end

      expect(status).to be_nil
      expect(output).to eq('')
      expect(gone?('26.43')).to be(true)
    end
  end

  describe 'cleaning up after mmdc' do
    it 'kills a child that stayed in the group mmdc was given' do
      Dir.mktmpdir do |dir|
        pidfile = File.join(dir, 'child.pid')

        run_fake_mmdc(dir, pidfile, escape: false)

        expect(dies?(File.read(pidfile).to_i)).to be(true)
      end
    end

    # A child that leaves the group is out of reach of the kill and still
    # holds the pipe, so reading to EOF waits on IT: one escaped Chromium
    # held a 30s case open for 301.7s.
    it 'stops waiting on the pipe when a child escapes the group' do
      stub_const('MermaidDiff::DRAIN_GRACE', 0.3)

      Dir.mktmpdir do |dir|
        pidfile = File.join(dir, 'child.pid')

        status, output = run_fake_mmdc(dir, pidfile, escape: true)

        expect(status).to be_success
        expect(output).to eq('')
      ensure
        kill_quietly(File.read(pidfile).to_i) if File.size?(pidfile)
      end
    end
  end

  describe 'asking sirena for a verdict' do
    it 'accepts a source sirena can render' do
      expect(harness.send(:sirena_verdict, trivial_source)).to be(:accepts)
    end

    # Only the mmdc half had a deadline. mmdc accepts this source in 7.2s and
    # sirena was still rendering it 60s in, so one probe like it stalled every
    # verdict after it and the report never arrived. The guard is here so a
    # regression fails this example instead of wedging the suite.
    it 'gives up on a source sirena cannot finish' do
      stub_const('MermaidDiff::CASE_TIMEOUT', 0.5)
      source = "packet-beta\n0-2000000: \"x\"\n"

      verdict = Timeout.timeout(guard) { harness.send(:sirena_verdict, source) }

      expect(verdict).to be(:rejects)
    end

    # Parslet recurses once per nesting level and runs out of stack before it
    # can report a parse failure. Measured: 200 levels raise an ordinary
    # error, 400 already blow the stack. 2,000 leaves room for a deeper stack
    # than this one. SystemStackError is not a StandardError, so it took the
    # whole run down instead of being one rejected probe.
    it 'answers instead of crashing when the parser runs out of stack' do
      deep = "flowchart LR\n#{"  subgraph s\n" * 2000}  A --> B\n#{"  end\n" * 2000}"

      expect(harness.send(:sirena_verdict, deep)).to be(:rejects)
    end
  end

  describe 'asking mermaid for a verdict' do
    it 'treats a missing process status as infrastructure failure' do
      result = MmdcOracle.verdict('probe') do |input, _output|
        raise 'unexpected canary run' unless input == 'probe'

        [nil, 'case timed out']
      end

      expect([result.verdict, result.diagnostic]).to eq([:error, 'case timed out'])
    end

    it 'treats success without an SVG as infrastructure failure' do
      result = MmdcOracle.verdict('probe') do |input, _output|
        raise 'unexpected canary run' unless input == 'probe'

        [true, 'no SVG was written']
      end

      expect([result.verdict, result.diagnostic]).to eq([:error, 'no SVG was written'])
    end

    # mmdc can fail to spawn long after the version check passed — the
    # process table fills up while Chromium is started once per case. That
    # used to abort the sweep with a traceback.
    it 'reports an infrastructure failure when mmdc cannot be spawned' do
      verdict = nil

      only('mmdc', nil) do
        expect { verdict = harness.send(:mermaid_verdict, trivial_source) }
          .to output(/mmdc/).to_stderr
      end

      expect(verdict).to be(:error)
    end

    # The pipe's write end was closed by hand right after the spawn, so a
    # spawn that raised never got there. One descriptor went per failure, and
    # a run that keeps going through them runs the harness out of them.
    it 'does not leak a descriptor when mmdc cannot be spawned' do
      only('mmdc', nil) do
        failing_verdict
        before = open_descriptors

        20.times { failing_verdict }

        expect(open_descriptors).to eq(before)
      end
    end

    it 'uses a canary to separate source rejection from a broken browser' do
      rejected = Dir.mktmpdir do |dir|
        prefix_path(fake_mmdc(dir, rejecting_probe_mmdc)) do
          harness.send(:mermaid_verdict, "not a diagram\n")
        end
      end

      expect(rejected).to be(:rejects)

      broken = nil
      only('mmdc', broken_browser_mmdc) do
        expect { broken = harness.send(:mermaid_verdict, trivial_source) }
          .to output(/browser launch failed/).to_stderr
      end
      expect(broken).to be(:error)
    end
  end

  # The version check runs before any per-case deadline applies, so a wedged
  # mmdc used to hang the harness here with nothing to stop it.
  describe 'checking the oracle' do
    it 'continues when mmdc reports the pinned version' do
      only('mmdc', version_mmdc(MermaidDiff::EXPECTED_CLI)) do
        expect(harness.send(:check_oracle)).to be_nil
      end
    end

    it 'aborts when mmdc reports a different version' do
      only('mmdc', version_mmdc('11.11.0')) do
        expect { harness.send(:check_oracle) }
          .to raise_error(SystemExit)
          .and output(/mmdc is 11\.11\.0, expected 11\.12\.0/).to_stderr
      end
    end

    it 'gives up on an mmdc that never answers instead of hanging on it' do
      stub_const('MermaidDiff::VERSION_TIMEOUT', 1)

      only('mmdc', wedge('20.31')) do
        expect { Timeout.timeout(guard) { harness.send(:check_oracle) } }
          .to raise_error(SystemExit).and output(/missing or not answering/).to_stderr
      end

      expect(gone?('20.31')).to be(true)
    end
  end

  describe 'running the harness as a program' do
    it 'exits zero only when every verdict agrees' do
      mixed = "#{trivial_source}%%%%\nnot a diagram\n"
      _agree_out, agree_err, agree_status = run_harness(trivial_source)
      mixed_out, mixed_err, mixed_status = run_harness(mixed)
      over_out, over_err, over_status = run_harness(
        "flowchart LR\n  A[reject-by-fake]\n",
        mmdc: selective_mmdc
      )
      failed_out, failed_err, failed_status = run_harness(trivial_source, mmdc: unavailable_mmdc)

      actual = [
        agree_status.exitstatus,
        agree_err,
        mixed_status.exitstatus,
        mixed_out,
        mixed_err,
        over_status.exitstatus,
        over_out,
        over_err,
        failed_status.exitstatus,
        failed_out,
        failed_err
      ]
      expected = [
        0,
        '',
        1,
        "GAP              not a diagram\n\n" \
          "2 probes: 1 agree, 1 gaps, 0 over-accepted, 0 mmdc failures\n",
        '',
        1,
        "OVER-ACCEPTANCE  flowchart LR |   A[reject-by-fake]\n\n" \
          "1 probes: 0 agree, 0 gaps, 1 over-accepted, 0 mmdc failures\n",
        '',
        1,
        "MMDC FAILED      flowchart LR |   A --> B\n\n" \
          "1 probes: 0 agree, 0 gaps, 0 over-accepted, 1 mmdc failures\n",
        "  mmdc: browser launch failed\n"
      ]

      expect(actual).to eq(expected)
    end

    it 'passes the only-gaps flag through to the report' do
      source = "not a diagram\n%%%%\nflowchart LR\n  A[reject-by-fake]\n"

      stdout, stderr, status = run_harness(source, '--only-gaps', mmdc: selective_mmdc)

      expected = [
        1,
        "GAP              not a diagram\n\n" \
          "2 probes: 0 agree, 1 gaps, 1 over-accepted, 0 mmdc failures\n",
        ''
      ]

      expect([status.exitstatus, stdout, stderr]).to eq(expected)
    end
  end

  describe 'splitting a probe file into records' do
    it 'splits on a line that is exactly the separator' do
      expect(records_in("flowchart LR\n%%%%\n  A --> B\n"))
        .to eq(["flowchart LR\n", "  A --> B\n"])
    end

    # mmdc 11.12.0 accepts `%%%%` followed by blanks as a comment, so a probe
    # may hold that line for real. Splitting there handed the two halves
    # verdicts the source itself never had.
    it 'keeps a separator line with trailing blanks as content' do
      source = "flowchart LR\n%%%%   \n  A --> B\n"

      expect(records_in(source)).to eq([source])
    end

    it 'unescapes a separator the source itself needed' do
      expect(records_in("flowchart LR\n\\%%%%\n  A --> B\n"))
        .to eq(["flowchart LR\n%%%%\n  A --> B\n"])
    end

    it 'leaves the backslash on a line that is not a separator' do
      source = "flowchart LR\n\\%%%%   \n  A --> B\n"

      expect(records_in(source)).to eq([source])
    end

    # The one source you could not write used to be `\%%%%` on its own line,
    # because the escape rewrote it to `%%%%` and left a doubled backslash
    # doubled. mmdc 11.12.0 renders the intended source and sirena rejects it;
    # both accept the transformed source containing the bare `%%%%` line.
    it 'writes a literal escape character with one more of them' do
      expect(records_in("flowchart LR\n\\\\%%%%\n  A --> B\n"))
        .to eq(["flowchart LR\n\\%%%%\n  A --> B\n"])
    end

    # mmdc renders a source that is not valid UTF-8 and sirena rejects it, so
    # the probe is a gap the harness should report. Reading the file as text
    # raised out of String#split instead, before a single case in it had run.
    it 'loads a probe that is not valid UTF-8' do
      source = "flowchart LR\n  A[\xFF\xFE]\n".b

      expect(records_in(source)).to eq([source.dup.force_encoding(Encoding::UTF_8)])
    end

    it 'keeps the bytes of such a probe exactly as they were written' do
      source = "flowchart LR\n  A[\xFF\xFE]\n".b

      expect(records_in(source).first.b).to eq(source)
    end
  end

  # These strings are cut down from real mmdc 11.12.0 output. Both error
  # renderings have the same root role; only the syntax-error page puts its
  # style element in the XHTML namespace.
  describe "reading mermaid's verdict off an SVG" do
    it 'accepts an intentional error diagram' do
      expect(oracle_verdict(intentional_error_svg)).to be(:accepts)
    end

    it 'rejects a rendered syntax-error page' do
      expect(oracle_verdict(syntax_error_svg)).to be(:rejects)
    end

    it 'requires the error role as well as an XHTML style' do
      svg = '<svg aria-roledescription="flowchart-v2">' \
            '<style xmlns="http://www.w3.org/1999/xhtml">text{fill:red;}</style></svg>'

      expect(oracle_verdict(svg)).to be(:accepts)
    end

    it 'ignores the word error everywhere but the root element' do
      svg = '<svg id="my-svg" class="flowchart" role="graphics-document document" ' \
            'aria-roledescription="flowchart-v2">' \
            '<style>.error-icon{fill:#552222;}</style>' \
            '<g class="node"><span>Syntax error in text</span></g></svg>'

      expect(oracle_verdict(svg)).to be(:accepts)
    end

    # A source can put the marker itself into the document. mmdc renders
    # `accDescr: aria-roledescription=#quot;error#quot;` and drops it into
    # <desc> with the quotes intact, so reading the whole document calls a
    # diagram mermaid drew a rejection. Cut from that output.
    it 'ignores the error role when it sits below the root element' do
      svg = '<svg id="my-svg" role="graphics-document document" ' \
            'aria-roledescription="flowchart-v2" aria-describedby="chart-desc-my-svg">' \
            '<desc id="chart-desc-my-svg">aria-roledescription="error"</desc>' \
            '<g class="node"/></svg>'

      expect(oracle_verdict(svg)).to be(:accepts)
    end
  end

  describe 'sharing the mmdc oracle with corpus verification' do
    it 'uses SVG contents rather than exit status alone' do
      Dir.mktmpdir do |dir|
        intentional = File.join(dir, 'intentional.mmd')
        syntax_error = File.join(dir, 'syntax-error.mmd')
        File.write(intentional, intentional_error_svg)
        File.write(syntax_error, syntax_error_svg)

        prefix_path(fake_mmdc(dir, copying_mmdc)) do
          expect(corpus_harness.send(:local_mmdc_verdict, intentional)).to be(:accepts)
          expect(corpus_harness.send(:local_mmdc_verdict, syntax_error)).to be(:rejects)
        end
      end
    end

    it 'maps every local verdict to the matching row update' do
      Dir.mktmpdir do |dir|
        entries = {
          'accept.mmd' => intentional_error_svg,
          'reject.mmd' => syntax_error_svg,
          'error.mmd' => '<svg/>'
        }.map do |name, contents|
          path = File.join(dir, name)
          File.write(path, contents)
          { path: path }
        end
        rows = entries.map do |entry|
          { 'case' => entry[:path], 'verdict' => 'invalid', 'evidence' => 'sidecar rejected it' }
        end

        prefix_path(fake_mmdc(dir, corpus_verdict_mmdc)) do
          expect { corpus_harness.send(:verify_invalid!, rows, entries) }
            .to output(/checked 3 invalid case\(s\).*1 promoted to valid/).to_stderr
        end

        expected = [
          ['valid', 'local mmdc renders it (sidecar rejection was stale)'],
          ['invalid', 'local mmdc rejects it too'],
          ['invalid', 'local mmdc could not be run']
        ]

        expect(rows.map { |row| [row['verdict'], row['evidence']] }).to eq(expected)
      end
    end
  end

  describe 'showing a probe in the report' do
    let(:verdicts) do
      [
        MermaidDiff::Verdict.new("same accepts\n", :accepts, :accepts),
        MermaidDiff::Verdict.new("same rejects\n", :rejects, :rejects),
        MermaidDiff::Verdict.new("gap\n", :rejects, :accepts),
        MermaidDiff::Verdict.new("over\n", :accepts, :rejects),
        MermaidDiff::Verdict.new("accept unavailable\n", :accepts, :error),
        MermaidDiff::Verdict.new("reject unavailable\n", :rejects, :error)
      ]
    end

    it 'prints labels and totals from the verdict states' do
      expected = <<~OUTPUT
        GAP              gap
        OVER-ACCEPTANCE  over
        MMDC FAILED      accept unavailable
        MMDC FAILED      reject unavailable

        6 probes: 2 agree, 1 gaps, 1 over-accepted, 2 mmdc failures
      OUTPUT

      expect { harness.send(:report, verdicts, only_gaps: false) }
        .to output(expected).to_stdout
    end

    it 'limits details to gaps without changing the totals' do
      expected = <<~OUTPUT
        GAP              gap

        6 probes: 2 agree, 1 gaps, 1 over-accepted, 2 mmdc failures
      OUTPUT

      expect { harness.send(:report, verdicts, only_gaps: true) }
        .to output(expected).to_stdout
    end

    # Leading whitespace is often the whole point of a probe, so only the
    # trailing newline goes and the rest of the line is left alone.
    it 'folds a record onto one line and keeps its indentation' do
      expect(harness.send(:one_line, "flowchart LR\n  A --> B\n"))
        .to eq('flowchart LR |   A --> B')
    end

    # A record may hold bytes UTF-8 cannot name, and the regexes that fold it
    # raise on those. Only the display is scrubbed: both tools were asked
    # about the real bytes.
    it 'shows a record whose bytes are not valid UTF-8' do
      source = +"flowchart LR\n  A[\xFF]\n"
      source.force_encoding(Encoding::UTF_8)

      expect(harness.send(:one_line, source)).to eq("flowchart LR |   A[\uFFFD]")
    end
  end

  # Longer than any example here needs, so a regression that hangs fails the
  # example instead of stalling the suite.
  def guard
    5
  end

  def trivial_source
    "flowchart LR\n  A --> B\n"
  end

  def run_harness(source, *options, mmdc: accepting_mmdc)
    Dir.mktmpdir do |dir|
      probe = File.join(dir, 'probe.txt')
      File.write(probe, source)
      bin = fake_mmdc(dir, mmdc)
      Open3.capture3(
        { 'PATH' => "#{bin}:#{ENV.fetch('PATH')}" },
        RbConfig.ruby,
        File.expand_path('../../scripts/mermaid_diff.rb', __dir__),
        *options,
        probe
      )
    end
  end

  def oracle_verdict(svg)
    MmdcOracle.verdict('probe') do |_input, output|
      File.write(output, svg)
      [true, '']
    end.verdict
  end

  def intentional_error_svg
    '<svg aria-roledescription="error"><style>.error-icon{fill:#552222;}</style></svg>'
  end

  def syntax_error_svg
    '<svg aria-roledescription="error">' \
      '<style xmlns="http://www.w3.org/1999/xhtml">.error-icon{fill:#552222;}</style></svg>'
  end

  # Runs one probe with mmdc gone, swallowing the note it prints about it.
  def failing_verdict
    capture_stderr { harness.send(:mermaid_verdict, trivial_source) }
  end

  def capture_stderr
    old = $stderr
    $stderr = StringIO.new
    yield
  ensure
    $stderr = old
  end

  # Every descriptor this process holds. /dev/fd lists them on both macOS and
  # Linux, and the reading itself costs the same on either side of a count.
  def open_descriptors
    Dir.children('/dev/fd').size
  end

  def dies?(pid)
    settles { alive?(pid) }
  end

  # A real `ps` that answers slowly, so the window between the last poll and
  # the kill is wide enough to land in on purpose rather than by luck.
  def slow_ps
    "#!/bin/sh\n/bin/sleep 0.8\nexec /bin/ps \"$@\"\n"
  end

  # A program that starts, leaves a child behind, and then never answers.
  # Every caller passes its own sleep duration, so the process table can be
  # searched for exactly its processes and no example sees another's.
  def wedge(seconds)
    "#!/bin/sh\n/bin/sleep #{seconds} &\nexec /bin/sleep #{seconds}\n"
  end

  def gone?(seconds)
    settles { `/bin/ps -eo command=`.include?("sleep #{seconds}") }
  end

  # SIGKILL lands asynchronously and a killed process stays in the table until
  # someone reaps it, so reading the table the instant the signal goes out
  # reports a process that is already on its way down as still there.
  def settles
    Timeout.timeout(guard) { sleep 0.02 while yield }
    true
  rescue Timeout::Error
    false
  end

  def records_in(text)
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'probe.txt')
      File.binwrite(path, text)
      harness.send(:probes, [path])
    end
  end

  # A parent in a process group of its own whose child sits in yet another —
  # the shape puppeteer gives mmdc and Chromium. Built with fork because
  # execing a fresh ruby costs seconds on a cold gem path.
  def spawn_tree
    Dir.mktmpdir do |dir|
      pidfile = File.join(dir, 'child.pid')
      parent = fork do
        Process.setpgid(0, 0)
        File.write(pidfile, Process.spawn('sleep', '120', pgroup: true))
        sleep 120
      ensure
        exit!(0)
      end
      spawned << parent
      child = await_pid(pidfile)
      spawned << child
      [own_group_leader(parent), child]
    end
  end

  def await_pid(pidfile)
    Timeout.timeout(guard) do
      sleep 0.01 until File.exist?(pidfile) && File.read(pidfile).match?(/\A\d+\z/)
    end
    File.read(pidfile).to_i
  end

  # The fork writes its pidfile only once it has its own group, so this holds
  # by the time the examples run. It is checked because kill_group signals a
  # whole group: a parent still in ours would take the suite down with it.
  def own_group_leader(pid)
    raise "pid #{pid} is not its own process group leader" unless Process.getpgid(pid) == pid

    pid
  end

  # Runs a fake mmdc that leaves a child holding the pipe it inherited, then
  # exits. With escape:, that child moves into a process group of its own the
  # way puppeteer starts Chromium; without it, it stays in mmdc's group.
  def run_fake_mmdc(dir, pidfile, escape:)
    script = escape ? escaping_child(pidfile) : child_in_the_group(pidfile)

    prefix_path(fake_mmdc(dir, script)) do
      Timeout.timeout(guard) do
        harness.send(:run_mmdc, File.join(dir, 'in.mmd'), File.join(dir, 'out.svg'))
      end
    end
  end

  # Puts one shell script on PATH under the name mmdc and hands back the
  # directory to prepend.
  def fake_mmdc(dir, script)
    bin = File.join(dir, 'bin')
    Dir.mkdir(bin)
    File.write(File.join(bin, 'mmdc'), script)
    File.chmod(0o755, File.join(bin, 'mmdc'))
    bin
  end

  def rejecting_probe_mmdc
    <<~'SH'
      #!/bin/sh
      if /usr/bin/grep -q '^flowchart LR$' "$2"; then
        printf '%s\n' '<svg aria-roledescription="flowchart-v2"><style/></svg>' > "$4"
        exit 0
      fi
      printf '%s\n' 'syntax error' >&2
      exit 1
    SH
  end

  def broken_browser_mmdc
    <<~'SH'
      #!/bin/sh
      printf '%s\n' 'browser launch failed' >&2
      exit 1
    SH
  end

  def copying_mmdc
    <<~SH
      #!/bin/sh
      /bin/cp "$2" "$4"
    SH
  end

  def accepting_mmdc
    <<~'SH'
      #!/bin/sh
      if [ "$1" = "--version" ]; then
        printf '%s\n' '11.12.0'
        exit 0
      fi
      printf '%s\n' '<svg aria-roledescription="flowchart-v2"><style/></svg>' > "$4"
    SH
  end

  def selective_mmdc
    <<~'SH'
      #!/bin/sh
      if [ "$1" = "--version" ]; then
        printf '%s\n' '11.12.0'
        exit 0
      fi
      if /usr/bin/grep -q 'reject-by-fake' "$2"; then
        printf '%s\n' '<svg aria-roledescription="error"><style xmlns="http://www.w3.org/1999/xhtml"/></svg>' > "$4"
      else
        printf '%s\n' '<svg aria-roledescription="flowchart-v2"><style/></svg>' > "$4"
      fi
    SH
  end

  def unavailable_mmdc
    <<~'SH'
      #!/bin/sh
      if [ "$1" = "--version" ]; then
        printf '%s\n' '11.12.0'
        exit 0
      fi
      printf '%s\n' 'browser launch failed'
      exit 1
    SH
  end

  def corpus_verdict_mmdc
    <<~SH
      #!/bin/sh
      case "$2" in
        *accept.mmd|*reject.mmd) /bin/cp "$2" "$4" ;;
        *) exit 1 ;;
      esac
    SH
  end

  def version_mmdc(version)
    "#!/bin/sh\nprintf '%s\\n' '#{version}'\n"
  end

  # The child writes its pid only once it has left the group, and mmdc waits
  # for that, so the escape has always happened by the time mmdc exits. It
  # used to race the group kill and usually lose, and the example passed
  # without ever testing an escaped child.
  def escaping_child(pidfile)
    perl = %q(perl -e 'setpgrp(0,0); open(F, ">", $ARGV[0]) or die; ) +
           %q(print F $$; close F; exec("/bin/sleep", "20.29")')
    "#!/bin/sh\n#{perl} '#{pidfile}' &\n" \
      "while [ ! -s '#{pidfile}' ]; do sleep 0.01; done\n"
  end

  def child_in_the_group(pidfile)
    "#!/bin/sh\n/bin/sleep 20.29 &\necho $! > '#{pidfile}'\n"
  end

  # PATH becomes this one directory, so the real program cannot be reached.
  # A nil script leaves the directory empty — the program is simply gone.
  def only(program, script, &block)
    Dir.mktmpdir do |dir|
      if script
        File.write(File.join(dir, program), script)
        File.chmod(0o755, File.join(dir, program))
      end
      with_path(dir, &block)
    end
  end

  def prefix_path(dir, &block)
    with_path("#{dir}:#{ENV.fetch('PATH')}", &block)
  end

  def with_path(path)
    old = ENV.fetch('PATH')
    ENV['PATH'] = path
    yield
  ensure
    ENV['PATH'] = old
  end

  def alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH, Errno::EPERM
    false
  end

  def kill_quietly(pid)
    Process.kill('KILL', pid)
  rescue Errno::ESRCH
    nil
  ensure
    begin
      Process.waitpid(pid, Process::WNOHANG)
    rescue Errno::ECHILD
      nil
    end
  end
end
