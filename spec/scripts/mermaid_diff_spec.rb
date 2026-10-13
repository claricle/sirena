# frozen_string_literal: true

require "open3"
# RbConfig arrives with RubyGems, not with the interpreter. Running Ruby with
# `--disable-gems` raises NameError on it. The example at :587 calls
# `RbConfig.ruby` to re-invoke
# the current interpreter, so requiring it here is what makes that example
# independent of how the suite was launched.
require "rbconfig"
require "stringio"
require "timeout"
require "tmpdir"

require_relative "../support/mermaid_diff_spec_support"

# The harness is a program, not a library. Loading it into a module runs the
# definitions without the main block, and keeps its methods and constants off
# Object for the rest of the suite.
unless defined?(MermaidDiff)
  MermaidDiff = Module.new
  load File.expand_path("../../scripts/mermaid_diff.rb", __dir__), MermaidDiff
end
unless defined?(CorpusVerdicts)
  CorpusVerdicts = Module.new
  load File.expand_path("../../scripts/corpus_verdicts.rb", __dir__),
       CorpusVerdicts
end

# Actions that several examples observe separately. Each one performs the real
# operation and returns what it observed, so the examples that split the
# observations still run the operation themselves.
module MermaidDiffLocalHelpers
  def observe_stderr
    old = $stderr
    $stderr = StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = old
  end

  # [verdict, stderr] for a probe run with mmdc gone.
  def spawn_failure
    verdict = nil
    stderr = nil
    only("mmdc", nil) do
      stderr = observe_stderr do
        verdict = harness.send(:mermaid_verdict, trivial_source)
      end
    end
    [verdict, stderr]
  end

  # Descriptors held before and after `count` failed spawns. The first
  # failure runs before the first reading so one-time setup is not counted.
  def descriptors_across_failures(count)
    only("mmdc", nil) do
      failing_verdict
      before = open_descriptors
      count.times { failing_verdict }
      return [before, open_descriptors]
    end
  end

  def rejecting_probe_verdict
    Dir.mktmpdir do |dir|
      prefix_path(fake_mmdc(dir, rejecting_probe_mmdc)) do
        harness.send(:mermaid_verdict, "not a diagram\n")
      end
    end
  end

  # [verdict, stderr] for a probe run against a browser that cannot launch.
  def broken_browser_run
    verdict = nil
    stderr = observe_stderr do
      only("mmdc", broken_browser_mmdc) do
        verdict = harness.send(:mermaid_verdict, trivial_source)
      end
    end
    [verdict, stderr]
  end

  # Runs the oracle check against a wedged mmdc under the harness guard and
  # returns [error class, stderr] so callers see the abort, not the exit.
  def wedged_check(seconds)
    stub_const("MermaidDiff::VERSION_TIMEOUT", 1)
    error = nil
    stderr = observe_stderr do
      only("mmdc", wedge(seconds)) do
        Timeout.timeout(guard) { harness.send(:check_oracle) }
      rescue SystemExit => e
        error = e
      end
    end
    [error, stderr]
  end

  def corpus_verdict_for(svg, script)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "case.mmd")
      File.write(path, svg)
      prefix_path(fake_mmdc(dir, script)) do
        corpus_harness.send(:local_mmdc_verdict, path)
      end
    end
  end

  # Runs verify_invalid! over an accepted, a rejected and a broken case.
  # Returns the rows after the update, the error count and what it printed.
  def verify_invalid_run
    Dir.mktmpdir do |dir|
      entries, rows = verify_cases(dir)
      errors = nil
      stderr = observe_stderr do
        prefix_path(fake_mmdc(dir, corpus_verdict_mmdc)) do
          errors = corpus_harness.send(:verify_invalid!, rows, entries)
        end
      end
      [rows.map { |row| [row["verdict"], row["evidence"]] }, errors, stderr]
    end
  end

  def verify_cases(dir)
    contents = { "accept.mmd" => intentional_error_svg,
                 "reject.mmd" => syntax_error_svg,
                 "error.mmd" => "<svg/>" }
    entries = contents.map do |name, text|
      path = File.join(dir, name)
      File.write(path, text)
      { path: path }
    end
    rows = entries.map do |entry|
      { "case" => entry[:path], "verdict" => "invalid",
        "evidence" => "sidecar rejected it" }
    end
    [entries, rows]
  end

  def verify_without_mmdc
    environment = ENV.keys
      .grep(/\A(?:BUNDLE|BUNDLER|RUBY)/)
      .to_h { |key| [key, nil] }
    environment["PATH"] = "/nonexistent"
    environment["SIRENA_ALLOW_TEST_MMDC"] = "1"
    environment["SIRENA_MMDC_TEST_BIN"] = "/nonexistent/mmdc"
    Open3.capture3(
      environment, RbConfig.ruby,
      File.expand_path("../../scripts/corpus_verdicts.rb", __dir__),
      "--verify", "gitgraph"
    )
  end
end

# Every example that breaks `ps` puts a real broken `ps` on PATH, and every
# process tree uses real processes — a stub would only prove that the rescue
# matches what the stub was told to raise.
RSpec.describe MermaidDiff, :aggregate_failures do
  include MermaidDiffSpecSupport::Helpers
  include MermaidDiffLocalHelpers

  subject(:harness) { Class.new { include MermaidDiff }.new }

  let(:corpus_harness) { Class.new { include CorpusVerdicts }.new }
  let(:spawned) { [] }

  # The harness reads the process table with `ps` and signals process groups.
  # Windows has neither, so the program cannot run there and there is nothing
  # here to check. Without this the whole windows-latest column went red while
  # every other platform passed.
  before { skip("the harness is POSIX-only") if Gem.win_platform? }

  after { spawned.each { |pid| kill_quietly(pid) } }

  describe "classifying a verdict" do
    {
      %i[accepts accepts] => [:agree, true],
      %i[rejects rejects] => [:agree, true],
      %i[rejects accepts] => [:gap, false],
      %i[accepts rejects] => [:over_acceptance, false],
      %i[accepts error] => [:infrastructure, false],
      %i[rejects error] => [:infrastructure, false],
    }.each do |(sirena, mermaid), (kind, agreement)|
      it "maps sirena #{sirena} with mermaid #{mermaid} to #{kind}" do
        verdict = MermaidDiff::Verdict.new("source", sirena, mermaid)

        expect([verdict.kind, verdict.agree?]).to eq([kind, agreement])
      end
    end
  end

  # The descendant sweep, the deadline wait, and mmdc process cleanup moved to
  # HardenedMmdc (spec/scripts/hardened_mmdc_spec.rb) when corpus_verdicts.rb
  # started sharing this hardening instead of calling mmdc through a bare
  # Open3.capture3.

  describe "asking sirena for a verdict" do
    it "accepts a source sirena can render" do
      expect(harness.send(:sirena_verdict, trivial_source)).to be(:accepts)
    end

    # Only the mmdc half had a deadline. mmdc accepts this source in 7.2s and
    # sirena was still rendering it 60s in, so one probe like it stalled every
    # verdict after it and the report never arrived. The guard is here so a
    # regression fails this example instead of wedging the suite.
    it "gives up on a source sirena cannot finish" do
      stub_const("HardenedMmdc::CASE_TIMEOUT", 0.5)
      source = "packet-beta\n0-2000000: \"x\"\n"

      verdict = Timeout.timeout(guard) { harness.send(:sirena_verdict, source) }

      expect(verdict).to be(:rejects)
    end

    # Parslet recurses once per nesting level and runs out of stack before it
    # can report a parse failure. Measured: 200 levels raise an ordinary
    # error, 400 already blow the stack. 2,000 leaves room for a deeper stack
    # than this one. SystemStackError is not a StandardError, so it took the
    # whole run down instead of being one rejected probe.
    it "answers instead of crashing when the parser runs out of stack" do
      deep = "flowchart LR\n#{"  subgraph s\n" * 2000}  " \
             "A --> B\n#{"  end\n" * 2000}"

      expect(harness.send(:sirena_verdict, deep)).to be(:rejects)
    end
  end

  describe "asking mermaid for a verdict" do
    let(:timeout_text) { "case timed out" }
    let(:missing_text) { "no SVG was written" }

    it "treats a missing process status as infrastructure failure" do
      result = MmdcOracle.verdict("probe") do |input, _output|
        raise "unexpected canary run" unless input == "probe"

        [nil, timeout_text]
      end

      expect([result.verdict, result.diagnostic]).to eq([:error, timeout_text])
    end

    it "treats success without an SVG as infrastructure failure" do
      result = MmdcOracle.verdict("probe") do |input, _output|
        raise "unexpected canary run" unless input == "probe"

        [true, missing_text]
      end

      expect([result.verdict, result.diagnostic]).to eq([:error, missing_text])
    end

    # mmdc can fail to spawn long after the version check passed — the
    # process table fills up while Chromium is started once per case. That
    # used to abort the sweep with a traceback.
    context "when mmdc cannot be spawned" do
      let(:failure) { spawn_failure }

      it "reports an infrastructure failure" do
        expect(failure.first).to be(:error)
      end

      it "says so on stderr" do
        expect(failure.last).to include("mmdc")
      end
    end

    # The pipe's write end was closed by hand right after the spawn, so a
    # spawn that raised never got there. One descriptor went per failure, and
    # a run that keeps going through them runs the harness out of them.
    it "does not leak a descriptor when mmdc cannot be spawned" do
      before, after = descriptors_across_failures(20)

      expect(after).to eq(before)
    end

    it "separates source rejection from a broken browser with a canary" do
      expect(rejecting_probe_verdict).to be(:rejects)
    end

    context "when the browser cannot launch" do
      let(:run) { broken_browser_run }

      it "reports an infrastructure failure" do
        expect(run.first).to be(:error)
      end

      it "names the launch failure on stderr" do
        expect(run.last).to include("browser launch failed")
      end
    end

    context "when the canary run fails once" do
      let(:result) do
        MmdcOracle.verdict("probe") do |input, output|
          if input == "probe"
            [false, "browser launch failed once"]
          else
            File.write(output, "<svg/>")
            [true, "Generating single mermaid chart"]
          end
        end
      end

      # Real mmdc prints this to stdout even on a healthy canary run, so a
      # true positive here must keep it out of the reported diagnostic --
      # otherwise a probe failure report gets the canary's own success noise
      # appended to the text a developer reads to triage the gap.
      it "does not call a transient renderer failure a source rejection" do
        expect([result.verdict, result.diagnostic])
          .to eq([:error, "browser launch failed once"])
      end
    end
  end

  # The version check runs before any per-case deadline applies, so a wedged
  # mmdc used to hang the harness here with nothing to stop it.
  describe "checking the oracle" do
    it "continues when mmdc reports the pinned version" do
      only("mmdc", version_mmdc(MermaidDiff::EXPECTED_CLI)) do
        expect(harness.send(:check_oracle)).to be_nil
      end
    end

    it "aborts when mmdc reports a different version" do
      only("mmdc", version_mmdc("11.11.0")) do
        expect { harness.send(:check_oracle) }
          .to raise_error(SystemExit)
          .and output(/mmdc is 11\.11\.0, expected 11\.12\.0/).to_stderr
      end
    end

    context "when mmdc never answers" do
      it "gives up with the harness's own message instead of hanging" do
        error, stderr = wedged_check("20.31")

        expect([error.class, stderr])
          .to match([SystemExit, /missing or not answering/])
      end

      it "leaves no wedged process behind" do
        wedged_check("20.32")

        expect(gone?("20.32")).to be(true)
      end
    end
  end

  describe "running the harness as a program" do
    it "exits zero when every verdict agrees" do
      _out, err, status = run_harness(trivial_source)

      expect([status.exitstatus, err]).to eq([0, ""])
    end

    context "when a verdict disagrees" do
      let(:run) { run_harness("#{trivial_source}%%%%\nnot a diagram\n") }
      let(:report) do
        "GAP              not a diagram\n\n" \
          "2 probes: 1 agree, 1 gaps, 0 over-accepted, 0 mmdc failures\n"
      end

      it "exits one and reports the gap" do
        out, err, status = run

        expect([status.exitstatus, out, err]).to eq([1, report, ""])
      end
    end

    context "when mmdc rejects what sirena accepts" do
      let(:run) do
        run_harness("flowchart LR\n  A[reject-by-fake]\n",
                    mmdc: selective_mmdc)
      end
      let(:report) do
        "OVER-ACCEPTANCE  flowchart LR |   A[reject-by-fake]\n\n" \
          "1 probes: 0 agree, 0 gaps, 1 over-accepted, 0 mmdc failures\n"
      end

      it "exits one and reports over-acceptance" do
        out, err, status = run

        expect([status.exitstatus, out, err]).to eq([1, report, ""])
      end
    end

    context "when mmdc is unavailable" do
      let(:run) { run_harness(trivial_source, mmdc: unavailable_mmdc) }
      let(:report) do
        "MMDC FAILED      flowchart LR |   A --> B\n\n" \
          "1 probes: 0 agree, 0 gaps, 0 over-accepted, 1 mmdc failures\n"
      end

      it "exits one and reports the mmdc failure" do
        out, err, status = run

        expect([status.exitstatus, out, err])
          .to eq([1, report, "  mmdc: browser launch failed\n"])
      end
    end

    context "with the only-gaps flag" do
      let(:source) do
        "not a diagram\n%%%%\nflowchart LR\n  A[reject-by-fake]\n"
      end
      let(:report) do
        "GAP              not a diagram\n\n" \
          "2 probes: 0 agree, 1 gaps, 1 over-accepted, 0 mmdc failures\n"
      end

      it "passes the flag through to the report" do
        stdout, stderr, status = run_harness(source, "--only-gaps",
                                             mmdc: selective_mmdc)

        expect([status.exitstatus, stdout, stderr]).to eq([1, report, ""])
      end
    end

    it "runs when invoked through a relative script path" do
      stdout, stderr, status = run_harness(trivial_source, relative: true)

      expect([status.exitstatus, stdout, stderr]).to eq(
        [0, "\n1 probes: 1 agree, 0 gaps, 0 over-accepted, 0 mmdc failures\n",
         ""],
      )
    end
  end

  describe "splitting a probe file into records" do
    it "splits on a line that is exactly the separator" do
      expect(records_in("flowchart LR\n%%%%\n  A --> B\n"))
        .to eq(["flowchart LR\n", "  A --> B\n"])
    end

    it "splits a CRLF separator" do
      expect(records_in("flowchart LR\r\n%%%%\r\n  A --> B\r\n"))
        .to eq(["flowchart LR\r\n", "  A --> B\r\n"])
    end

    it "accepts a separator at the end of a file" do
      expect(records_in("flowchart LR\n%%%%")).to eq(["flowchart LR\n"])
    end

    # mmdc 11.12.0 accepts `%%%%` followed by blanks as a comment, so a probe
    # may hold that line for real. Splitting there handed the two halves
    # verdicts the source itself never had.
    it "keeps a separator line with trailing blanks as content" do
      source = "flowchart LR\n%%%%   \n  A --> B\n"

      expect(records_in(source)).to eq([source])
    end

    it "unescapes a separator the source itself needed" do
      expect(records_in("flowchart LR\n\\%%%%\n  A --> B\n"))
        .to eq(["flowchart LR\n%%%%\n  A --> B\n"])
    end

    it "leaves the backslash on a line that is not a separator" do
      source = "flowchart LR\n\\%%%%   \n  A --> B\n"

      expect(records_in(source)).to eq([source])
    end

    # The one source you could not write used to be `\%%%%` on its own line,
    # because the escape rewrote it to `%%%%` and left a doubled backslash
    # doubled. mmdc 11.12.0 renders the intended source and sirena rejects it;
    # both accept the transformed source containing the bare `%%%%` line.
    it "writes a literal escape character with one more of them" do
      expect(records_in("flowchart LR\n\\\\%%%%\n  A --> B\n"))
        .to eq(["flowchart LR\n\\%%%%\n  A --> B\n"])
    end

    # mmdc renders a source that is not valid UTF-8 and sirena rejects it, so
    # the probe is a gap the harness should report. Reading the file as text
    # raised out of String#split instead, before a single case in it had run.
    it "loads a probe that is not valid UTF-8" do
      source = "flowchart LR\n  A[\xFF\xFE]\n".b

      expect(records_in(source)).to eq([source.dup.force_encoding(Encoding::UTF_8)])
    end

    it "keeps the bytes of such a probe exactly as they were written" do
      source = "flowchart LR\n  A[\xFF\xFE]\n".b

      expect(records_in(source).first.b).to eq(source)
    end

    it "loads all committed probe records" do
      paths = Dir[File.expand_path("../../scripts/probes/*.txt", __dir__)]
        .reject { |path| File.basename(path) == "shape_names.txt" }
        .sort

      expect(paths.size).to eq(3)
      expect(harness.send(:probes, paths).size).to eq(60)
    end
  end

  # These strings are cut down from real mmdc 11.12.0 output. Both error
  # renderings have the same root role; only the syntax-error page puts its
  # style element in the XHTML namespace.
  describe "reading mermaid's verdict off an SVG" do
    let(:root_error_text_svg) do
      '<svg id="my-svg" class="flowchart" ' \
        'role="graphics-document document" ' \
        'aria-roledescription="flowchart-v2">' \
        "<style>.error-icon{fill:#552222;}</style>" \
        '<g class="node"><span>Syntax error in text</span></g></svg>'
    end
    let(:nested_error_role_svg) do
      '<svg id="my-svg" role="graphics-document document" ' \
        'aria-roledescription="flowchart-v2" ' \
        'aria-describedby="chart-desc-my-svg">' \
        '<desc id="chart-desc-my-svg">aria-roledescription="error"</desc>' \
        '<g class="node"/></svg>'
    end

    it "accepts an intentional error diagram" do
      expect(oracle_verdict(intentional_error_svg)).to be(:accepts)
    end

    it "rejects a rendered syntax-error page" do
      expect(oracle_verdict(syntax_error_svg)).to be(:rejects)
    end

    # Keep the last two rows even though the first three look sufficient:
    # they are the only ones that raise ArgumentError/RuntimeError instead of
    # a parse error, which is what exercises valid_svg?'s rescue of rexml
    # wrapping the error in ParseException. Narrowing that rescue to
    # ArgumentError, or dropping these rows, would let a rexml version that
    # stops wrapping crash the sweep on damaged mmdc output while every
    # other row here stays green.
    [
      "", "plain text", "<svg>",
      "<?xml version='1.0' encoding='NOT-A-CHARSET'?><svg/>",
      "<svg>\xFF\xFE</svg>",
      "<svg>&#xZZ;</svg>"
    ].each do |svg|
      it "requires a valid SVG document: #{svg.inspect}" do
        expect(oracle_verdict(svg)).to be(:error)
      end
    end

    context "with the error role missing" do
      let(:xhtml_style_svg) do
        '<svg aria-roledescription="flowchart-v2">' \
          '<style xmlns="http://www.w3.org/1999/xhtml">text{fill:red;}' \
          "</style></svg>"
      end

      it "requires the error role as well as an XHTML style" do
        expect(oracle_verdict(xhtml_style_svg)).to be(:accepts)
      end
    end

    it "ignores the word error everywhere but the root element" do
      expect(oracle_verdict(root_error_text_svg)).to be(:accepts)
    end

    # A source can put the marker itself into the document. mmdc renders
    # `accDescr: aria-roledescription=#quot;error#quot;` and drops it into
    # <desc> with the quotes intact, so reading the whole document calls a
    # diagram mermaid drew a rejection. Cut from that output.
    it "ignores the error role when it sits below the root element" do
      expect(oracle_verdict(nested_error_role_svg)).to be(:accepts)
    end
  end

  describe "sharing the mmdc oracle with corpus verification" do
    it "accepts an intentional error diagram by its SVG contents" do
      verdict = corpus_verdict_for(intentional_error_svg, copying_mmdc)

      expect(verdict).to be(:accepts)
    end

    it "rejects a syntax-error page by its SVG contents" do
      verdict = corpus_verdict_for(syntax_error_svg, copying_mmdc)

      expect(verdict).to be(:rejects)
    end

    it "uses a real rejection diagnostic when mmdc exits nonzero" do
      verdict = corpus_verdict_for('not a diagram\n', rejecting_corpus_mmdc)

      expect(verdict).to be(:rejects)
    end

    context "when mapping every local verdict to a row update" do
      let(:run) { verify_invalid_run }

      it "reports how many cases it checked and promoted" do
        expect(run.last)
          .to match(/checked 3 invalid case\(s\).*1 promoted to valid/)
      end

      it "updates each row from its local verdict" do
        expect(run.first.map(&:first)).to eq(%w[valid invalid invalid])
      end

      it "records the evidence each local verdict produced" do
        expect(run.first.map(&:last)).to eq(
          ["local mmdc renders it (sidecar rejection was stale)",
           "local mmdc rejects it too", "local mmdc could not be run"],
        )
      end

      # The CLI's abort-on-broken-mmdc gate reads exactly this return value
      # (corpus_verdicts.rb:318-319) -- only the third row is a genuine
      # :error (mmdc could not be run), so it must be 1, not 3.
      it "counts only the case mmdc could not run as an error" do
        expect(run[1]).to eq(1)
      end
    end

    context "when mmdc cannot run during verification" do
      let(:run) { verify_without_mmdc }

      it "prints nothing to stdout" do
        expect(run[0]).to eq("")
      end

      it "says that verification failed" do
        expect(run[1]).to include("mmdc verification failed")
      end

      it "fails the verify command" do
        expect(run[2]).not_to be_success
      end
    end
  end

  describe "showing a probe in the report" do
    let(:verdicts) do
      [
        MermaidDiff::Verdict.new("same accepts\n", :accepts, :accepts),
        MermaidDiff::Verdict.new("same rejects\n", :rejects, :rejects),
        MermaidDiff::Verdict.new("gap\n", :rejects, :accepts),
        MermaidDiff::Verdict.new("over\n", :accepts, :rejects),
        MermaidDiff::Verdict.new("accept unavailable\n", :accepts, :error),
        MermaidDiff::Verdict.new("reject unavailable\n", :rejects, :error),
      ]
    end

    context "with the full report" do
      let(:expected) do
        <<~OUTPUT
          GAP              gap
          OVER-ACCEPTANCE  over
          MMDC FAILED      accept unavailable
          MMDC FAILED      reject unavailable

          6 probes: 2 agree, 1 gaps, 1 over-accepted, 2 mmdc failures
        OUTPUT
      end

      it "prints labels and totals from the verdict states" do
        expect { harness.send(:report, verdicts, only_gaps: false) }
          .to output(expected).to_stdout
      end
    end

    context "with only the gaps" do
      let(:expected) do
        <<~OUTPUT
          GAP              gap

          6 probes: 2 agree, 1 gaps, 1 over-accepted, 2 mmdc failures
        OUTPUT
      end

      it "limits details to gaps without changing the totals" do
        expect { harness.send(:report, verdicts, only_gaps: true) }
          .to output(expected).to_stdout
      end
    end

    # Leading whitespace is often the whole point of a probe, so only the
    # trailing newline goes and the rest of the line is left alone.
    it "folds a record onto one line and keeps its indentation" do
      expect(harness.send(:one_line, "flowchart LR\n  A --> B\n"))
        .to eq("flowchart LR |   A --> B")
    end

    # A record may hold bytes UTF-8 cannot name, and the regexes that fold it
    # raise on those. Only the display is scrubbed: both tools were asked
    # about the real bytes.
    it "shows a record whose bytes are not valid UTF-8" do
      source = (+"flowchart LR\n  A[\xFF]\n").force_encoding(Encoding::UTF_8)

      expect(harness.send(:one_line, source))
        .to eq("flowchart LR |   A[\uFFFD]")
    end

    it "escapes terminal control bytes in a record" do
      source = "flowchart LR\n  A[\x1B]52;c;secret\x07\rB]\n"

      expect(harness.send(:one_line, source))
        .to eq('flowchart LR |   A[\\x1B]52;c;secret\\x07\\x0DB]')
    end
  end

  include MermaidDiffSpecSupport::Helpers
end
