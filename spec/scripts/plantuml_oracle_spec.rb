# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"
require "yaml"
require "timeout"
require "fileutils"
require_relative "../../scripts/plantuml_oracle"

module PlantumlOracleSpecSupport
  def diagram_svg
    '<svg xmlns="http://www.w3.org/2000/svg" ' \
      'data-diagram-type="SEQUENCE"><g/></svg>'
  end

  # PlantUML's error image: no data-diagram-type, the message in a text node.
  def error_svg
    '<svg xmlns="http://www.w3.org/2000/svg">' \
      "<text>Syntax Error? (Assumed diagram type: sequence)</text></svg>"
  end

  def good = "@startuml\nC -> D\n@enduml\n"
  def bad = "@startuml\nclass Other {\n@enduml\n"

  def run_of(status: 0, stdout: "", stderr: "", timed_out: false,
             spawn_error: nil)
    PlantumlOracle::Execution.new(
      status: status, stdout: stdout, stderr: stderr,
      timed_out: timed_out, spawn_error: spawn_error
    )
  end

  def valid_run = run_of(stdout: diagram_svg)

  def rejected_run
    run_of(status: 200, stdout: error_svg, stderr: "ERROR\n2\nSyntax Error?\n")
  end

  def timed_out_run = run_of(status: nil, timed_out: true)

  def error_image_exit0_run = run_of(stdout: error_svg)
  def diagram_exit200_run = run_of(status: 200, stdout: diagram_svg)
  def empty_run = run_of(stdout: "")
  def truncated_run = run_of(stdout: "<svg><g>")
  def bare_svg_run = run_of(stdout: "<svg/>")
  def unexpected_exit_run = run_of(status: 1, stdout: error_svg)
  def signal_run = run_of(status: nil)
  def missing_binary_run = run_of(status: nil, spawn_error: "no such file")

  def missing_java_run
    run_of(status: 127, stderr: "java: command not found")
  end

  def missing_graphviz_run
    run_of(status: 200, stdout: error_svg,
           stderr: 'java.io.IOException: Cannot run program "dot"')
  end

  def out_of_memory_run
    run_of(status: 200, stderr: "java.lang.OutOfMemoryError: Java heap space")
  end

  # Stubs the process boundary. `by_source` maps a source to an Execution;
  # version probes get realistic output.
  def runner_for(by_source)
    lambda do |command, input, _timeout|
      case command.first
      when "java" then run_of(stderr: %(openjdk version "21.0.2" 2024-01-16))
      when "dot" then run_of(stderr: "dot - graphviz version 15.1.1 (2026)")
      else
        return plantuml_version if version?(command)

        by_source.fetch(input) { valid_run }
      end
    end
  end

  def version?(command) = command.include?("--version")

  def plantuml_version = run_of(stdout: "PlantUML version 1.2026.6 / abc")

  def alive_runner(extra = {})
    runs = {
      good => valid_run,
      bad => rejected_run,
      PlantumlOracle::CANARY_VALID => valid_run,
      PlantumlOracle::CANARY_INVALID => rejected_run,
    }
    runner_for(runs.merge(extra))
  end

  def canary_runner(valid:, invalid:)
    runner_for(PlantumlOracle::CANARY_VALID => valid,
               PlantumlOracle::CANARY_INVALID => invalid)
  end

  # [timed_out, finished well inside the 20s guard] for a command that must
  # be killed after `limit` seconds. Call from an example tagged :speed.
  def killed_promptly(command, limit)
    run = nil
    elapsed = wall_time do
      run = Timeout.timeout(20) do
        PlantumlOracle::Runner.call(command, "", limit)
      end
    end
    [run.timed_out, elapsed < 10]
  end

  def spying_runner(judged)
    broken = runner_for(PlantumlOracle::CANARY_VALID => rejected_run)
    lambda do |command, input, timeout|
      judged << input
      broken.call(command, input, timeout)
    end
  end

  def good_record_fields
    {
      "plantuml" => "1.2026.6 / abc",
      "java" => "21.0.2",
      "graphviz" => "15.1.1",
      "source_sha256" => Digest::SHA256.hexdigest(good),
      "svg_sha256" => Digest::SHA256.hexdigest(diagram_svg),
    }
  end

  def recorded_source_verdicts(records)
    records.to_h do |record|
      id = record.fetch("id")
      [id, [record.fetch("verdict"), record.fetch("source_sha256")]]
    end
  end

  def expected_source_verdicts(sources)
    sources.to_h do |id, source|
      [id, [a_string_matching(/\A(?:valid|rejected)\z/),
            Digest::SHA256.hexdigest(source)]]
    end
  end

  def recorded_toolchains(document, records)
    fields = document.fetch("toolchain").keys
    records = records.map { |record| record.slice(*fields) }
    [document.fetch("toolchain"), records]
  end

  # The error `refresh` raises for this runner, or nil when it succeeds.
  def refresh_failure(cases, path, runner)
    PlantumlOracle.refresh(cases, path, runner: runner)
    nil
  rescue PlantumlOracle::CanaryFailure,
         PlantumlOracle::InfrastructureFailure => e
    e
  end
end

RSpec.describe PlantumlOracle do
  include PlantumlOracleSpecSupport

  def judge_with(run)
    described_class.judge("x", runner: ->(*) { run })
  end

  describe "classification" do
    {
      "rendered diagram, exit 0" => %i[valid valid_run],
      "error image, exit 200 (invalid seed)" => %i[rejected rejected_run],
      "error image that exits 0" => %i[rejected error_image_exit0_run],
      "diagram image with exit 200" => %i[infrastructure diagram_exit200_run],
      "exit 0, empty stdout" => %i[infrastructure empty_run],
      "exit 0, truncated svg" => %i[infrastructure truncated_run],
      "exit 0, svg that is neither diagram nor error" =>
        %i[infrastructure bare_svg_run],
      "unexpected exit code" => %i[infrastructure unexpected_exit_run],
      "killed by a signal" => %i[infrastructure signal_run],
      "binary missing (seeded infrastructure failure)" =>
        %i[infrastructure missing_binary_run],
      "java missing" => %i[infrastructure missing_java_run],
      "graphviz missing, error image exits 200" =>
        %i[infrastructure missing_graphviz_run],
      "out of memory" => %i[infrastructure out_of_memory_run],
      "timeout" => %i[infrastructure timed_out_run],
    }.each do |name, (state, build)|
      it "#{name} is #{state}" do
        expect(judge_with(public_send(build)).state).to eq(state)
      end
    end

    it "does not take exit 0 alone as proof that an error image is valid" do
      expect(judge_with(run_of(stdout: error_svg)).state).not_to eq(:valid)
    end

    it "gives infrastructure failure no verdict" do
      expect(judge_with(timed_out_run).verdict?).to be(false)
    end
  end

  describe "the real runner" do
    before { skip("POSIX-only") if Gem.win_platform? }

    it "kills a process that outlives the timeout, children included", :speed do
      hang = ["sh", "-c", "sleep 30 & wait"]

      expect(killed_promptly(hang, 1)).to eq([true, true])
    end

    it "reports a missing binary as a spawn error, not an exception" do
      command = ["plantuml-does-not-exist-xyz", "--pipe"]
      run = PlantumlOracle::Runner.call(command, "", 5)

      expect(run.spawn_error).to be_a(String)
    end

    it "classifies a missing binary as infrastructure end to end" do
      verdict = described_class.judge("x", binary: "no-such-plantuml-xyz")

      expect(verdict.state).to eq(:infrastructure)
    end

    it "feeds stdin and returns stdout and the exit status" do
      run = PlantumlOracle::Runner.call(["sh", "-c", "cat; exit 3"], "hello", 5)

      expect([run.stdout, run.status, run.timed_out]).to eq(["hello", 3, false])
    end
  end

  describe ".canary!" do
    it "passes when the oracle renders good and refuses bad" do
      expect { described_class.canary!(runner: alive_runner) }
        .not_to raise_error
    end

    it "fails when the valid canary is not valid" do
      runner = canary_runner(valid: rejected_run, invalid: rejected_run)

      expect { described_class.canary!(runner: runner) }
        .to raise_error(PlantumlOracle::CanaryFailure, /valid canary/)
    end

    it "fails when the oracle accepts everything" do
      runner = canary_runner(valid: valid_run, invalid: valid_run)

      expect { described_class.canary!(runner: runner) }
        .to raise_error(PlantumlOracle::CanaryFailure, /invalid canary/)
    end
  end

  describe ".refresh" do
    let(:dir) { Dir.mktmpdir("plantuml-oracle") }
    let(:path) { File.join(dir, "verdicts.yml") }
    let(:prior) { "prior: verdicts\n" }
    let(:cases) { { "b/bad" => bad, "a/good" => good } }

    before { File.write(path, prior) }
    after { FileUtils.remove_entry(dir) }

    context "when every case has a verdict" do
      let(:records) do
        described_class.refresh(cases, path, runner: alive_runner)
        YAML.load_file(path).fetch("verdicts")
      end

      it "writes every verdict in id order" do
        expect(records.map { |r| [r["id"], r["verdict"]] })
          .to eq([%w[a/good valid], %w[b/bad rejected]])
      end

      it "records versions and content hashes in each record" do
        expect(records.first).to include(good_record_fields)
      end
    end

    context "when one case hits an infrastructure failure" do
      let(:runner) { alive_runner(bad => timed_out_run) }

      it "raises naming the case" do
        expect(refresh_failure(cases, path, runner))
          .to be_a(PlantumlOracle::InfrastructureFailure)
          .and have_attributes(message: %r{b/bad})
      end

      it "leaves prior verdicts untouched" do
        refresh_failure(cases, path, runner)

        expect(File.read(path)).to eq(prior)
      end

      it "leaves no temp file behind" do
        refresh_failure(cases, path, runner)

        expect(Dir.children(dir)).to eq(["verdicts.yml"])
      end
    end

    context "when the canary fails" do
      let(:judged) { [] }

      it "raises a canary failure" do
        expect(refresh_failure(cases, path, spying_runner(judged)))
          .to be_a(PlantumlOracle::CanaryFailure)
      end

      it "leaves prior verdicts untouched, and judges no case" do
        refresh_failure(cases, path, spying_runner(judged))

        expect([File.read(path), judged & cases.values]).to eq([prior, []])
      end
    end

    context "when a version cannot be read" do
      let(:runner) do
        no_dot = run_of(status: nil, spawn_error: "no dot")
        lambda do |command, input, timeout|
          next no_dot if command.first == "dot"

          alive_runner.call(command, input, timeout)
        end
      end

      it "raises naming the probe" do
        expect(refresh_failure(cases, path, runner))
          .to be_a(PlantumlOracle::InfrastructureFailure)
          .and have_attributes(message: /dot/)
      end

      it "leaves prior verdicts untouched" do
        refresh_failure(cases, path, runner)

        expect(File.read(path)).to eq(prior)
      end
    end
  end

  describe "the committed verdicts" do
    let(:root) { File.expand_path("../..", __dir__) }
    let(:corpus) { File.join(root, "spec/plantuml") }
    let(:document) do
      YAML.load_file(File.join(corpus, "oracle-verdicts.yml"))
    end
    let(:records) { document.fetch("verdicts") }

    it "covers every corpus case exactly once in case-id order" do
      case_ids = described_class.load_cases(corpus).keys.sort

      expect(records.map { |record| record.fetch("id") }).to eq(case_ids)
    end

    it "records only verdicts whose source hashes match the corpus" do
      sources = described_class.load_cases(corpus)

      expect(recorded_source_verdicts(records))
        .to match(expected_source_verdicts(sources))
    end

    it "carries the pinned toolchain in every verdict" do
      pin = JSON.parse(File.read(File.join(corpus, "pin.json")))
      toolchain = pin.dig("oracle", "toolchain")

      expect(recorded_toolchains(document, records))
        .to match([toolchain, all(eq(toolchain))])
    end
  end

  describe "against the real binary" do
    before do
      tools = %w[plantuml java dot]
      available = tools.all? do |t|
        system("which", t, out: File::NULL, err: File::NULL)
      end
      skip("plantuml, java or dot not on PATH") unless available
    end

    it "passes its own canary" do
      expect { described_class.canary! }.not_to raise_error
    end

    it "classifies a syntax error as rejected" do
      expect(described_class.judge(bad).state).to eq(:rejected)
    end
  end
end
