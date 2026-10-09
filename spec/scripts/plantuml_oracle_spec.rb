# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "yaml"
require "timeout"
require "fileutils"
require_relative "../../scripts/plantuml_oracle"

module PlantumlOracleSpecSupport
  def diagram_svg = '<svg xmlns="http://www.w3.org/2000/svg" data-diagram-type="SEQUENCE"><g/></svg>'
  # PlantUML's error image: no data-diagram-type, the message in a text node.
  def error_svg = '<svg xmlns="http://www.w3.org/2000/svg"><text>Syntax Error? (Assumed diagram type: sequence)</text></svg>'
  def good = "@startuml\nC -> D\n@enduml\n"
  def bad = "@startuml\nclass Other {\n@enduml\n"

  def run_of(status: 0, stdout: "", stderr: "", timed_out: false, spawn_error: nil)
    PlantumlOracle::Execution.new(status: status, stdout: stdout, stderr: stderr, timed_out: timed_out, spawn_error: spawn_error)
  end

  def valid_run = run_of(stdout: diagram_svg)
  def rejected_run = run_of(status: 200, stdout: error_svg, stderr: "ERROR\n2\nSyntax Error?\n")

  # Stubs the process boundary. `by_source` maps a source to an Execution;
  # version probes get realistic output.
  def runner_for(by_source)
    lambda do |command, input, _timeout|
      case command.first
      when "java" then run_of(stderr: %(openjdk version "21.0.2" 2024-01-16))
      when "dot" then run_of(stderr: "dot - graphviz version 15.1.1 (20260805.0921)")
      else
        return run_of(stdout: "PlantUML version 1.2026.6 / abc") if command.include?("--version")

        by_source.fetch(input) { valid_run }
      end
    end
  end

  def alive_runner(extra = {})
    runs = {
      good => valid_run,
      bad => rejected_run,
      PlantumlOracle::CANARY_VALID => valid_run,
      PlantumlOracle::CANARY_INVALID => rejected_run,
    }
    runner_for(runs.merge(extra))
  end
end

RSpec.describe PlantumlOracle do
  include PlantumlOracleSpecSupport

  def judge_with(run)
    described_class.judge("x", runner: ->(*) { run })
  end

  describe "classification" do
    {
      "rendered diagram, exit 0" => [:valid, lambda(&:valid_run)],
      "error image, exit 200 (invalid seed)" => [:rejected, lambda(&:rejected_run)],
      "error image that exits 0" => [:rejected, ->(s) { s.run_of(stdout: s.error_svg) }],
      "diagram image with exit 200" => [:infrastructure, ->(s) { s.run_of(status: 200, stdout: s.diagram_svg) }],
      "exit 0, empty stdout" => [:infrastructure, ->(s) { s.run_of(stdout: "") }],
      "exit 0, truncated svg" => [:infrastructure, ->(s) { s.run_of(stdout: "<svg><g>") }],
      "exit 0, svg that is neither diagram nor error" => [:infrastructure, ->(s) { s.run_of(stdout: "<svg/>") }],
      "unexpected exit code" => [:infrastructure, ->(s) { s.run_of(status: 1, stdout: s.error_svg) }],
      "killed by a signal" => [:infrastructure, ->(s) { s.run_of(status: nil) }],
      "binary missing (seeded infrastructure failure)" => [:infrastructure, ->(s) { s.run_of(status: nil, spawn_error: "No such file or directory - plantuml") }],
      "java missing" => [:infrastructure, ->(s) { s.run_of(status: 127, stderr: "java: command not found") }],
      "graphviz missing, error image exits 200" => [:infrastructure, ->(s) { s.run_of(status: 200, stdout: s.error_svg, stderr: "java.io.IOException: Cannot run program \"dot\"") }],
      "out of memory" => [:infrastructure, ->(s) { s.run_of(status: 200, stderr: "java.lang.OutOfMemoryError: Java heap space") }],
      "timeout" => [:infrastructure, ->(s) { s.run_of(status: nil, timed_out: true) }],
    }.each do |name, (state, build)|
      it "#{name} is #{state}" do
        expect(judge_with(build.call(self)).state).to eq(state)
      end
    end

    it "treats exit code alone as insufficient: exit 0 does not make an error image valid" do
      expect(judge_with(run_of(stdout: error_svg)).state).not_to eq(:valid)
    end

    it "gives infrastructure failure no verdict" do
      expect(judge_with(run_of(status: nil, timed_out: true)).verdict?).to be(false)
    end
  end

  describe "the real runner" do
    before { skip("POSIX-only") if Gem.win_platform? }

    it "kills a process that outlives the timeout instead of hanging, children included", :speed do
      run = nil
      elapsed = wall_time do
        run = Timeout.timeout(20) { PlantumlOracle::Runner.call(["sh", "-c", "sleep 30 & wait"], "", 1) }
      end

      expect([run.timed_out, elapsed < 10]).to eq([true, true])
    end

    it "reports a missing binary as a spawn error, not an exception" do
      run = PlantumlOracle::Runner.call(["plantuml-does-not-exist-xyz", "--pipe"], "", 5)

      expect(run.spawn_error).to be_a(String)
    end

    it "classifies a missing binary as infrastructure end to end" do
      expect(described_class.judge("x", binary: "plantuml-does-not-exist-xyz").state).to eq(:infrastructure)
    end

    it "feeds stdin and returns stdout and the exit status" do
      run = PlantumlOracle::Runner.call(["sh", "-c", "cat; exit 3"], "hello", 5)

      expect([run.stdout, run.status, run.timed_out]).to eq(["hello", 3, false])
    end
  end

  describe ".canary!" do
    it "passes when the oracle renders the good source and refuses the bad one" do
      expect { described_class.canary!(runner: alive_runner) }.not_to raise_error
    end

    it "fails when the valid canary is not valid" do
      runner = runner_for(PlantumlOracle::CANARY_VALID => rejected_run, PlantumlOracle::CANARY_INVALID => rejected_run)

      expect { described_class.canary!(runner: runner) }.to raise_error(PlantumlOracle::CanaryFailure, /valid canary/)
    end

    it "fails when the oracle accepts everything" do
      runner = runner_for(PlantumlOracle::CANARY_VALID => valid_run, PlantumlOracle::CANARY_INVALID => valid_run)

      expect { described_class.canary!(runner: runner) }.to raise_error(PlantumlOracle::CanaryFailure, /invalid canary/)
    end
  end

  describe ".refresh" do
    let(:dir) { Dir.mktmpdir("plantuml-oracle") }
    let(:path) { File.join(dir, "verdicts.yml") }
    let(:prior) { "prior: verdicts\n" }
    let(:cases) { { "b/bad" => bad, "a/good" => good } }

    before { File.write(path, prior) }
    after { FileUtils.remove_entry(dir) }

    it "writes every verdict with versions and content hashes in each record" do
      described_class.refresh(cases, path, runner: alive_runner)
      records = YAML.load_file(path).fetch("verdicts")

      expect(records.map { |r| [r["id"], r["verdict"]] }).to eq([%w[a/good valid], %w[b/bad rejected]])
      expect(records.first).to include(
        "plantuml" => "1.2026.6 / abc", "java" => "21.0.2", "graphviz" => "15.1.1",
        "source_sha256" => Digest::SHA256.hexdigest(good), "svg_sha256" => Digest::SHA256.hexdigest(diagram_svg)
      )
    end

    it "leaves prior verdicts untouched when one case hits an infrastructure failure" do
      runner = alive_runner(bad => run_of(status: nil, timed_out: true))

      expect { described_class.refresh(cases, path, runner: runner) }.to raise_error(PlantumlOracle::InfrastructureFailure, %r{b/bad})
      expect(File.read(path)).to eq(prior)
    end

    it "leaves prior verdicts untouched, and judges no case, when the canary fails" do
      judged = []
      broken = runner_for(PlantumlOracle::CANARY_VALID => rejected_run)
      spy = lambda do |command, input, timeout|
        judged << input
        broken.call(command, input, timeout)
      end

      expect { described_class.refresh(cases, path, runner: spy) }.to raise_error(PlantumlOracle::CanaryFailure)
      expect([File.read(path), judged & cases.values]).to eq([prior, []])
    end

    it "leaves prior verdicts untouched when a version cannot be read" do
      runner = lambda do |command, input, timeout|
        command.first == "dot" ? run_of(status: nil, spawn_error: "no dot") : alive_runner.call(command, input, timeout)
      end

      expect { described_class.refresh(cases, path, runner: runner) }.to raise_error(PlantumlOracle::InfrastructureFailure, /dot/)
      expect(File.read(path)).to eq(prior)
    end

    it "leaves no temp file behind after a failed run" do
      runner = alive_runner(bad => run_of(status: nil, timed_out: true))
      expect { described_class.refresh(cases, path, runner: runner) }.to raise_error(PlantumlOracle::InfrastructureFailure)

      expect(Dir.children(dir)).to eq(["verdicts.yml"])
    end
  end

  describe "against the real binary" do
    before do
      skip("plantuml, java or dot not on PATH") unless %w[plantuml java dot].all? { |t| system("which", t, out: File::NULL, err: File::NULL) }
    end

    it "passes its own canary and classifies a syntax error as rejected" do
      expect { described_class.canary! }.not_to raise_error
      expect(described_class.judge(bad).state).to eq(:rejected)
    end
  end
end
