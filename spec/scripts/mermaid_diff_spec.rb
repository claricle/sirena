# frozen_string_literal: true

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

# Nothing here simulates a failure. Every example that breaks `ps` puts a real
# broken `ps` on PATH and every process tree is real processes — a stub would
# only prove that the rescue matches what the stub was told to raise.
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

    # Giving up on a wedged `ps` is not enough. It inherited the harness's
    # stdout and stderr, so leaving it running hands the wait to whoever is
    # reading our output: measured, the sweep returned in 0.30s and the
    # reader waited 21.29s for EOF.
    it 'kills a ps that never answers rather than leave it holding our output' do
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
    it 'gives up on an mmdc that never answers instead of hanging on it' do
      stub_const('MermaidDiff::VERSION_TIMEOUT', 1)

      only('mmdc', wedge('20.31')) do
        expect { Timeout.timeout(guard) { harness.send(:check_oracle) } }
          .to raise_error(SystemExit).and output(/missing or not answering/).to_stderr
      end

      expect(gone?('20.31')).to be(true)
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
    # doubled. mmdc renders that source and sirena rejects it, so the probe
    # for a real gap quietly became the bare `%%%%` source, which both accept.
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
  end

  describe 'showing a probe in the report' do
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
