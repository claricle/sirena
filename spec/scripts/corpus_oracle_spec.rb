# frozen_string_literal: true

require "fileutils"
require "open3"
require "rbconfig"
require "tmpdir"
require "yaml"

require_relative "../support/mermaid_diff_spec_support"
require_relative "../../scripts/corpus_oracle"

# CorpusVerdicts is a program, not a library: loaded into its own module, the
# way hardened_mmdc_spec.rb does, so classify and cases are reachable.
unless defined?(CorpusVerdicts)
  CorpusVerdicts = Module.new
  load File.expand_path("../../scripts/corpus_verdicts.rb", __dir__),
       CorpusVerdicts
end

# Runner doubles for the block CorpusOracle takes. They answer in the
# [status, diagnostic] shape HardenedMmdc.run_mmdc returns and always render
# the canary, so only the case under test varies.
module CorpusOracleSpecSupport
  LAUNCH_FAILURE = "Error: Failed to launch the browser process!"
  # What a stack looks like when mermaid threw, and when Puppeteer did.
  MERMAID_FRAME = "Parser3.parseError (/x/mermaid/dist/mermaid.js:104438:28)"
  PUPPETEER_FRAME = "    at ChromeLauncher.launch (/x/puppeteer-core/L.js:50)"

  def harness
    @harness ||= Class.new { include CorpusVerdicts }.new
  end

  def corpus_root
    File.expand_path("../../spec/mermaid", __dir__)
  end

  def provenance
    { "mmdc" => CorpusOracle::EXPECTED_CLI }
  end

  def rendered_svg
    '<svg aria-roledescription="flowchart-v2"><style/></svg>'
  end

  def runner_for(&)
    lambda do |input, output|
      if File.basename(input) == "canary.mmd"
        File.write(output, rendered_svg)
        next [true, ""]
      end

      yield(input, output)
    end
  end

  def accepting
    runner_for do |_input, output|
      File.write(output, rendered_svg)
      [true, ""]
    end
  end

  def failing_with(diagnostic, frame: MERMAID_FRAME)
    banner = "Generating single mermaid chart\n\n"
    runner_for do |_input, _output|
      [false, "#{banner}#{diagnostic}\n#{frame}\n"]
    end
  end

  # Same head both times; only the first stack runs through mermaid.
  def mermaid_then_puppeteer
    frames = [MERMAID_FRAME, PUPPETEER_FRAME]
    runner_for { |_input, _output| [false, "Error: x\n#{frames.shift}\n"] }
  end

  def error_page_svg
    '<svg aria-roledescription="error">' \
      '<style xmlns="http://www.w3.org/1999/xhtml"/></svg>'
  end

  # An error page on the first run; exit 0 with no SVG on every later one.
  def error_page_once
    calls = 0
    runner_for do |_input, output|
      File.write(output, error_page_svg) if (calls += 1) == 1
      [true, ""]
    end
  end

  def error_page_runner
    runner_for do |_input, output|
      File.write(output, error_page_svg)
      [true, ""]
    end
  end

  # Fails every canary after the first `count`, to prove it is re-checked.
  def canary_dies_after(count)
    seen = 0
    lambda do |input, output|
      seen += 1 if File.basename(input) == "canary.mmd"
      next [false, LAUNCH_FAILURE] if seen > count

      File.write(output, rendered_svg)
      [true, ""]
    end
  end

  def crashing_on(name)
    runner_for do |input, output|
      next [false, LAUNCH_FAILURE] if File.basename(input) == name

      File.write(output, rendered_svg)
      [true, ""]
    end
  end

  def corpus_entry(dir, name, rendered:)
    base = File.join(dir, name)
    source = "pie\n  title #{name}\n"
    File.write("#{base}.svg", rendered_svg) if rendered
    { type: "pie", path: "#{base}.mmd", base: base, source: source,
      digest: Digest::SHA256.hexdigest(source) }
  end

  def write_entries(dir, sources)
    sources.each_with_index.map do |(name, source), index|
      path = File.join(dir, "#{name}.mmd")
      File.write(path, source)
      { path: path, digest: Digest::SHA256.hexdigest(source),
        case: "t/#{index.to_s.rjust(3, '0')}_#{name}.mmd" }
    end
  end

  def refresh_with(runner)
    refresh_with_entries(entries, runner)
  end

  def refresh_with_entries(list, runner)
    CorpusOracle.refresh(list, provenance: provenance, path: out, &runner)
  end

  OracleRun = Struct.new(:out, :err, :status, :written, :verdicts)

  SANDBOX_SCRIPTS = %w[corpus_verdicts corpus_oracle hardened_mmdc
                       mmdc_oracle].freeze

  # The script resolves every path from its own location, so a copy of it
  # beside a three-case corpus can never touch the committed data.
  def sandbox_tree(root, seed)
    copy_scripts(File.join(root, "scripts"))
    write_pie_corpus(File.join(root, "spec", "mermaid"))
    File.write(oracle_file(root), seed) if seed
  end

  def copy_scripts(target)
    FileUtils.mkdir_p(target)
    scripts = File.expand_path("../../scripts", __dir__)
    SANDBOX_SCRIPTS.each { |n| FileUtils.cp("#{scripts}/#{n}.rb", target) }
  end

  # a and b are open; c has a rendered sidecar, so nothing asks mmdc about it.
  def write_pie_corpus(corpus)
    FileUtils.mkdir_p("#{corpus}/pie")
    %w[a b c].each { |n| File.write("#{corpus}/pie/#{n}.mmd", "pie\n#{n}\n") }
    File.write("#{corpus}/pie/c.svg", rendered_svg)
  end

  def oracle_file(root)
    File.join(root, "spec", "mermaid", "oracle-verdicts.yml")
  end

  def run_oracle(*args, mmdc:, seed: nil)
    Dir.mktmpdir do |dir|
      root = File.join(dir, "repo")
      sandbox_tree(root, seed)
      env = { "PATH" => "#{fake_mmdc(dir, mmdc)}:#{ENV.fetch('PATH')}" }
      out, err, status = Open3.capture3(env, RbConfig.ruby, script_in(root),
                                        "--oracle", *args)
      OracleRun.new(out, err, status, read_if_present(oracle_file(root)),
                    read_if_present(verdicts_file(root)))
    end
  end

  def verdicts_file(root)
    File.join(root, "spec", "mermaid", "corpus-verdicts.yml")
  end

  def script_in(root)
    File.join(root, "scripts", "corpus_verdicts.rb")
  end

  def read_if_present(file)
    File.read(file) if File.exist?(file)
  end

  def mermaid_rejecting_mmdc
    <<~'SH'
      #!/bin/sh
      if [ "$1" = "--version" ]; then
        printf '%s\n' '11.12.0'
        exit 0
      fi
      if /usr/bin/grep -q '^flowchart LR$' "$2"; then
        printf '%s\n' '<svg aria-roledescription="flowchart-v2"><style/></svg>' > "$4"
        exit 0
      fi
      printf '%s\n' 'Error: Parse error on line 1:' 'Parser3.parseError (x/mermaid.js:1:2)' >&2
      exit 1
    SH
  end

  # A mermaid-cli install (bin/mmdc beside node_modules/mermaid) reached
  # through a symlink on PATH, the way npm's global bin directory does it.
  def install_mmdc(root, on_path:, manifest: nil)
    bin = File.join(root, "bin", "mmdc")
    FileUtils.mkdir_p([File.dirname(bin), on_path])
    File.write(bin, "#!/bin/sh\n")
    FileUtils.chmod(0o755, bin)
    File.symlink(bin, File.join(on_path, "mmdc"))
    return unless manifest

    mermaid = File.join(root, "node_modules", "mermaid")
    FileUtils.mkdir_p(mermaid)
    File.write(File.join(mermaid, "package.json"), manifest)
  end

  def regenerated_verdicts(oracle)
    entries = harness.send(:cases, [])
    by_digest = harness.send(:index_by_digest, entries)
    entries.map do |entry|
      verdict, evidence = harness.send(:classify, entry,
                                       by_digest[entry[:digest]], oracle)
      { "case" => entry[:path].delete_prefix("#{corpus_root}/"),
        "verdict" => verdict, "evidence" => evidence }
    end
  end
end

RSpec.describe CorpusOracle do
  include CorpusOracleSpecSupport
  include MermaidDiffSpecSupport::Helpers

  let(:dir) { Dir.mktmpdir }
  let(:path) { File.join(dir, "case.mmd").tap { |p| File.write(p, "pie\n") } }
  let(:out) { File.join(dir, "oracle.yml") }

  after { FileUtils.remove_entry(dir) }

  describe ".judge" do
    it "accepts a source mmdc renders" do
      expect(described_class.judge(path, &accepting)).to eq(["accepts", nil])
    end

    it "rejects a source whose mermaid diagnostic repeats" do
      runner = failing_with("Error: Lexical error on line 1.")

      expect(described_class.judge(path, &runner))
        .to eq(["rejects", "Error: Lexical error on line 1."])
    end

    it "rejects when mmdc exits 0 with mermaid's error page" do
      expect(described_class.judge(path, &error_page_runner))
        .to eq(["rejects", "mermaid error page"])
    end

    it "treats a diagnostic that changes between runs as infrastructure" do
      calls = 0
      runner = runner_for { |_i, _o| [false, "Error: attempt #{calls += 1}"] }

      expect { described_class.judge(path, &runner) }
        .to raise_error(described_class::InfrastructureError, /differently/)
    end

    it "treats a second run that fails differently as infrastructure" do
      expect { described_class.judge(path, &error_page_once) }
        .to raise_error(described_class::InfrastructureError, /differently/)
    end

    {
      "a browser launch failure" => CorpusOracleSpecSupport::LAUNCH_FAILURE,
      "a missing browser" => "Error: Browser was not found at /nonexistent",
      "a lost browser target" => "Error: Protocol error: Target closed",
      "a crashed page" => "Error: Page crashed!",
      "a navigation during evaluate" =>
        "Error: Execution context was destroyed, most likely because " \
        "of a navigation",
      "a spawn failure" => "Error: spawn EAGAIN",
      "a dropped socket" => "Error: socket hang up",
      "a navigation timeout" =>
        "TimeoutError: Navigation timeout of 30000 ms exceeded",
    }.each do |name, diagnostic|
      it "never records #{name} as a rejection" do
        runner = failing_with(diagnostic,
                              frame: CorpusOracleSpecSupport::PUPPETEER_FRAME)

        expect { described_class.judge(path, &runner) }
          .to raise_error(described_class::InfrastructureError, /not a mermaid/)
      end
    end

    {
      "a stack trace with no diagnostic" => "    at Object.<anonymous> (x.js)",
      "a head that is not an error class" => "syntax error near token",
      "a node warning that mentions an error" =>
        "(node:1) Warning: Error: net::ERR_FAILED",
    }.each do |name, diagnostic|
      it "never records #{name} as a rejection even with a mermaid frame" do
        expect { described_class.judge(path, &failing_with(diagnostic)) }
          .to raise_error(described_class::InfrastructureError, /not a mermaid/)
      end
    end

    %w[notmermaid.js not-mermaid.js not+mermaid.js
       not@mermaid.js].each do |file|
      it "does not take #{file} for the mermaid bundle" do
        runner = failing_with("Error: x", frame: "    at f (/tmp/#{file}:5:1)")

        expect { described_class.judge(path, &runner) }
          .to raise_error(described_class::InfrastructureError, /not a mermaid/)
      end
    end

    it "needs mermaid's frame on the second run too" do
      expect { described_class.judge(path, &mermaid_then_puppeteer) }
        .to raise_error(described_class::InfrastructureError, /not a mermaid/)
    end

    it "never records a silent failure as a rejection" do
      runner = runner_for { |_input, _output| [false, ""] }

      expect { described_class.judge(path, &runner) }
        .to raise_error(described_class::InfrastructureError, /not a mermaid/)
    end

    it "keeps a rejection whose text echoes a word infrastructure uses" do
      head = "UnknownDiagramError: No diagram matches text: timeout reconnect"

      expect(described_class.judge(path, &failing_with(head)).last)
        .to eq(head)
    end

    it "reads a diagnostic that FORCE_COLOR wrapped in colour codes" do
      coloured = "\e[31m\e[39m\n\e[31mError: Parse error on line 2:\e[39m"

      expect(described_class.judge(path, &failing_with(coloured)).last)
        .to eq("Error: Parse error on line 2:")
    end

    it "treats a run killed after printing a diagnostic as infrastructure" do
      diagnostic = "Error: Lexical error on line 1."
      runner = runner_for { |_input, _output| [nil, diagnostic] }

      expect { described_class.judge(path, &runner) }
        .to raise_error(described_class::InfrastructureError, /killed/)
    end

    it "keeps a diagnostic with non-ASCII text readable" do
      runner = failing_with("Error: bad Citt\u00e0".b)

      expect(described_class.judge(path, &runner).last)
        .to eq("Error: bad Citt\u00e0")
    end

    it "replaces bytes that are not UTF-8 instead of crashing" do
      runner = failing_with("Error: bad \xFF input".b)

      expect(described_class.judge(path, &runner).last)
        .to eq("Error: bad \uFFFD input")
    end

    it "cuts a long diagnostic at a character, not in the middle of one" do
      runner = failing_with("Error: #{"\u00e0" * 200}".b)

      expect(described_class.judge(path, &runner).last)
        .to be_valid_encoding.and(have_attributes(length: 120))
    end
  end

  describe ".refresh" do
    let(:entries) do
      write_entries(dir, { "a" => "pie\n", "b" => "pie\n", "c" => "gantt\n" })
    end

    it "writes the rows in case order whatever order the entries arrive in" do
      refresh_with_entries(entries.reverse, accepting)

      expect(YAML.load_file(out)["cases"].map { |row| row["cases"] })
        .to eq([["t/000_a.mmd", "t/001_b.mmd"], ["t/002_c.mmd"]])
    end

    it "writes one row per distinct source, naming every case sharing it" do
      refresh_with(accepting)

      expect(YAML.load_file(out)["cases"].map { |row| row["cases"] })
        .to eq([["t/000_a.mmd", "t/001_b.mmd"], ["t/002_c.mmd"]])
    end

    it "writes rows that load_rows reads back by source hash" do
      refresh_with(accepting)

      expect(described_class.load_rows(out).keys)
        .to match_array(entries.map { |entry| entry[:digest] }.uniq)
    end

    it "writes verdicts that row_verdict understands" do
      refresh_with(accepting)

      rows = described_class.load_rows(out).values

      expect(rows.map { |row| described_class.row_verdict(row).first })
        .to eq(%w[valid valid])
    end

    it "records the provenance it was given" do
      refresh_with(accepting)

      expect(YAML.load_file(out)["provenance"]).to eq(provenance)
    end

    it "returns the rows it wrote" do
      rows = refresh_with(accepting)

      expect(rows).to eq(YAML.load_file(out)["cases"])
    end

    context "when one case hits an infrastructure failure" do
      before do
        File.write(out, "earlier\n")
        begin
          refresh_with(crashing_on("c.mmd"))
        rescue described_class::InfrastructureError
          nil
        end
      end

      it "leaves the earlier file untouched" do
        expect(File.read(out)).to eq("earlier\n")
      end
    end

    context "when the final canary fails" do
      before do
        refresh_with(canary_dies_after(1))
      rescue described_class::InfrastructureError
        nil
      end

      it "writes nothing" do
        expect(File).not_to exist(out)
      end
    end

    context "when the final rename fails" do
      before do
        FileUtils.mkdir_p(File.join(out, "occupied"))
        begin
          refresh_with(accepting)
        rescue SystemCallError
          nil
        end
      end

      it "leaves no temporary file behind" do
        expect(Dir.glob("#{out}.*.tmp")).to eq([])
      end
    end

    it "refuses to judge anything when the canary does not render" do
      expect { refresh_with(canary_dies_after(0)) }
        .to raise_error(described_class::InfrastructureError, /canary/)
    end

    it "checks the canary again after the last case" do
      expect { refresh_with(canary_dies_after(1)) }
        .to raise_error(described_class::InfrastructureError, /canary/)
    end
  end

  describe ".provenance" do
    let(:install) { File.join(dir, "install") }
    let(:on_path) { File.join(dir, "on_path") }

    before do
      FileUtils.mkdir_p(on_path)
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("PATH").and_return(on_path)
      allow(HardenedMmdc).to receive(:capture)
        .and_return("#{described_class::EXPECTED_CLI}\n")
    end

    it "names the mmdc and the mermaid it bundles" do
      skip("the harness is POSIX-only") if Gem.win_platform?
      install_mmdc(install, on_path: on_path,
                            manifest: '{"version":"11.4.2"}')

      expect(described_class.provenance)
        .to include("mmdc" => "11.12.0", "mermaid" => "11.4.2")
    end

    it "notes that the toolchain is not pinned" do
      expect(described_class.provenance)
        .to include("note" => a_string_matching(/not pinned/))
    end

    it "records the mermaid version as unknown when mmdc is not on PATH" do
      expect(described_class.provenance).to include("mermaid" => "unknown")
    end

    it "records the mermaid version as unknown without a bundled copy" do
      install_mmdc(install, on_path: on_path)

      expect(described_class.provenance).to include("mermaid" => "unknown")
    end

    [Errno::ENOENT, Timeout::Error].each do |failure|
      it "refuses when asking mmdc its version raises #{failure}" do
        allow(HardenedMmdc).to receive(:capture).and_raise(failure)

        expect { described_class.provenance }.to raise_error(
          described_class::InfrastructureError,
          "mmdc is missing or not answering, not 11.12.0",
        )
      end
    end
  end

  describe ".row_verdict" do
    let(:rejection) { { "verdict" => "rejects", "reason" => "Error: boom" } }

    it "maps accepts to valid" do
      expect(described_class.row_verdict({ "verdict" => "accepts" }).first)
        .to eq("valid")
    end

    it "maps rejects to invalid" do
      expect(described_class.row_verdict(rejection).first).to eq("invalid")
    end

    it "names the diagnostic in a rejection's evidence" do
      expect(described_class.row_verdict(rejection).last)
        .to include("Error: boom")
    end

    it "raises on a verdict it does not know instead of guessing" do
      expect { described_class.row_verdict({ "verdict" => "maybe" }) }
        .to raise_error(ArgumentError, /maybe/)
    end
  end

  describe ".load_rows" do
    it "is empty before any refresh has been committed" do
      expect(described_class.load_rows(out)).to eq({})
    end

    it "keys the committed rows by source hash" do
      File.write(out, { "cases" => [{ "sha256" => "abc" }] }.to_yaml)

      expect(described_class.load_rows(out).keys).to eq(["abc"])
    end
  end

  describe "classify with a committed oracle row" do
    let(:entry) do
      { type: "pie", path: "#{dir}/pie/1.mmd", base: "#{dir}/pie/1",
        source: "pie\n", digest: "abc" }
    end
    let(:oracle) { { "abc" => { "verdict" => "accepts" } } }

    before { FileUtils.mkdir_p("#{dir}/pie") }

    it "settles a case nothing else speaks for" do
      expect(harness.send(:classify, entry, [entry], oracle).first)
        .to eq("valid")
    end

    it "leaves the case unknown without that row" do
      expect(harness.send(:classify, entry, [entry], {}).first)
        .to eq("unknown")
    end

    it "does not let an oracle row outrank damage in the source" do
      damaged = entry.merge(source: "pie\\ntitle x")

      expect(harness.send(:classify, damaged, [damaged], oracle).first)
        .to eq("artifact")
    end

    it "settles a deliberate error diagram from its accepted render" do
      error_case = entry.merge(type: "error")

      expect(harness.send(:classify, error_case, [error_case], oracle).first)
        .to eq("valid")
    end

    it "calls a source in the error directory invalid when mermaid throws" do
      error_case = entry.merge(type: "error")
      thrown = { "abc" => { "verdict" => "rejects", "reason" => "Error: x" } }

      expect(harness.send(:classify, error_case, [error_case], thrown).first)
        .to eq("invalid")
    end

    it "does not let an oracle row outrank the case's own render" do
      File.write("#{entry[:base]}.svg", rendered_svg)
      rejecting = { "abc" => { "verdict" => "rejects", "reason" => "x" } }

      expect(harness.send(:classify, entry, [entry], rejecting).first)
        .to eq("valid")
    end

    it "does not let an oracle row outrank the case's own rejection" do
      File.write("#{entry[:base]}.error", "")

      expect(harness.send(:classify, entry, [entry], oracle).first)
        .to eq("invalid")
    end

    it "does not let an oracle row outrank a twin's rejection" do
      twin = entry.merge(path: "#{dir}/pie/2.mmd", base: "#{dir}/pie/2")
      File.write("#{twin[:base]}.error", "")

      expect(harness.send(:classify, entry, [entry, twin], oracle).first)
        .to eq("invalid")
    end
  end

  describe "oracle_targets" do
    let(:entries) do
      [corpus_entry(dir, "settled", rendered: true),
       corpus_entry(dir, "open", rendered: false),
       corpus_entry(dir, "refused", rendered: false)
         .tap { |e| File.write("#{e[:base]}.error", "") },
       corpus_entry(dir, "damaged", rendered: false)
         .tap { |e| e.merge!(source: "pie\\ntitle x", digest: "d") }]
    end
    let(:targets) do
      stub_const("CorpusVerdicts::CORPUS_ROOT", dir)
      by_digest = harness.send(:index_by_digest, entries)
      harness.send(:oracle_targets, entries, by_digest)
    end

    it "asks mmdc only about cases nothing else settles" do
      expect(targets.map { |target| target[:case] }).to eq(["open.mmd"])
    end

    it "labels a target with its path inside the corpus" do
      expect(targets.first).to eq(path: File.join(dir, "open.mmd"),
                                  digest: entries[1][:digest],
                                  case: "open.mmd")
    end
  end

  describe "the committed verdict files" do
    let(:verdicts_path) { File.join(corpus_root, "corpus-verdicts.yml") }

    it "reproduce corpus-verdicts.yml from classify and the oracle rows" do
      rows = regenerated_verdicts(described_class.load_rows)

      expect(rows.to_yaml).to eq(File.read(verdicts_path))
    end

    it "leave no case without a verdict" do
      verdicts = YAML.load_file(verdicts_path).map { |row| row["verdict"] }

      expect(verdicts.uniq).to contain_exactly("valid", "invalid", "artifact")
    end

    it "keep an oracle row only for sources still in the corpus" do
      digests = harness.send(:cases, []).map { |entry| entry[:digest] }

      expect(described_class.load_rows.keys - digests).to eq([])
    end
  end

  describe "the --oracle command" do
    let(:sentinel) { "cases: []\n" }

    # The fake mmdc is a shell script and HardenedMmdc reads the process
    # table with `ps`: neither exists on Windows.
    before { skip("the harness is POSIX-only") if Gem.win_platform? }

    context "when mmdc renders every case" do
      let(:run) { run_oracle(mmdc: accepting_mmdc) }

      it "reports how many cases it judged" do
        expect(run.err).to include("judged 2 case(s)")
      end

      it "writes one accepting row per open case" do
        rows = YAML.safe_load(run.written)["cases"]

        expect(rows.map { |row| [row["verdict"], row["cases"]] })
          .to eq([["accepts", ["pie/a.mmd"]], ["accepts", ["pie/b.mmd"]]])
      end

      it "settles the judged cases in the verdicts --write then emits" do
        run = run_oracle("--write", mmdc: accepting_mmdc)

        expect(YAML.safe_load(run.verdicts).map { |row| row["verdict"] })
          .to eq(%w[valid valid valid])
      end

      it "records the mmdc version the verdicts were measured with" do
        expect(YAML.safe_load(run.written)["provenance"]["mmdc"])
          .to eq("11.12.0")
      end
    end

    it "writes a rejection with the diagnostic mermaid gave" do
      run = run_oracle(mmdc: mermaid_rejecting_mmdc)

      expect(YAML.safe_load(run.written)["cases"].map { |row| row["reason"] })
        .to eq(["Error: Parse error on line 1:"] * 2)
    end

    context "when mmdc cannot render" do
      let(:run) { run_oracle(mmdc: unavailable_mmdc, seed: sentinel) }

      it "reports that nothing was written" do
        expect(run.err).to include("oracle refresh failed, nothing written")
      end

      it "exits with status 1" do
        expect(run.status.exitstatus).to eq(1)
      end

      it "leaves the committed oracle file untouched" do
        expect(run.written).to eq(sentinel)
      end
    end

    context "with a type filter" do
      let(:run) { run_oracle("pie", mmdc: accepting_mmdc, seed: sentinel) }

      it "refuses, because it would truncate the committed file" do
        expect(run.err).to include("need the whole corpus")
      end

      it "leaves the committed oracle file untouched" do
        expect(run.written).to eq(sentinel)
      end
    end

    %w[99.0.0 11.12.1 11.99.0].each do |version|
      it "refuses mmdc #{version}, not the one the verdicts were made with" do
        run = run_oracle(mmdc: version_mmdc(version))

        expect(run.err).to include("mmdc is #{version}, not 11.12.0")
      end
    end
  end
end
