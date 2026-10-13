# frozen_string_literal: true

require "spec_helper"
require "rake"
require "tmpdir"
require "stringio"

unless defined?(MermaidFixtureTasks)
  load File.expand_path("../../tasks/generate_mermaid_fixtures.rake",
                        __dir__)
end

RSpec.describe MermaidFixtureTasks do
  around do |example|
    original_application = Rake.application
    Rake.application = Rake::Application.new
    load File.expand_path("../../tasks/generate_mermaid_fixtures.rake",
                          __dir__)
    Dir.mktmpdir do |directory|
      Dir.chdir(directory) { example.run }
    end
  ensure
    Rake.application = original_application
  end

  def capture
    previous = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = previous
  end

  def seed_source(name, source, error: false)
    path = "spec/mermaid/flowchart/#{name}.mmd"
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, source)
    File.write(path.sub(".mmd", ".error"), "expected") if error
  end

  def fixture_process(input, output)
    success = File.read(input) == "good"
    File.write(output, "<svg><path/></svg>") if success
    ["", "Generating single mermaid chart\nfixture failure\n",
     instance_double(Process::Status, success?: success)]
  end

  context "when generating fixture outcomes" do
    let(:generator) { MermaidFixtureGenerator.new }
    let(:output) do
      capture do
        generator.generate_fixtures_for_type("flowchart")
      end
    end

    before do
      allow(MermaidToolchain).to receive(:command) { |*args|
        ["fake-cli", *args]
      }
      allow(Open3).to receive(:capture3) do |_environment, *command|
        fixture_process(command[command.index("-i") + 1],
                        command[command.index("-o") + 1])
      end
    end

    context "with fifty sources spanning all four outcomes" do
      before do
        seed_source("01-good", "good")
        seed_source("02-bad", "bad")
        seed_source("03-known", "bad", error: true)
        seed_source("04-surprise", "good", error: true)
        46.times { |index| seed_source("extra-#{index}", "good") }
      end

      let(:unexpected_logs) do
        output
        directory = "spec/fixtures_mermaid/flowchart"
        %w[_unexpected_failures.log _unexpected_successes.log].map do |name|
          File.read(File.join(directory, name))
        end
      end

      it "reports progress and correct and unexpected behavior separately" do
        expect(output).to include(".FEU", "[50/50]", "48/50 (96.0%)",
                                  "Unexpected behaviors: 2")
      end

      it "writes each unexpected log with the original basename and reason" do
        expect(unexpected_logs)
          .to eq(["02-bad: fixture failure",
                  "04-surprise: Should have failed but succeeded"])
      end

      it "separates successful fixtures by the source error marker" do
        output
        directories = %w[correct expected_errors]
        expect(directories.map do |directory|
          Dir.glob("spec/fixtures_mermaid/flowchart/#{directory}/*.svg").size
        end).to eq([47, 1])
      end
    end

    it "reports missing sources without creating a type directory" do
      expect([output, Dir.exist?("spec/fixtures_mermaid/flowchart")])
        .to eq(["\n🔄 Generating fixtures for: flowchart\n#{'-' * 60}\n" \
                "⚠️  No .mmd files found for flowchart\n", false])
    end

    context "with one successful source" do
      before { seed_source("good", "good") }

      it "prints a full pass rate without unexpected logs" do
        expect([output.include?("1/1 (100.0%)"), output.include?("Unexpected")])
          .to eq([true, false])
      end
    end
  end

  context "when comparing reference structures" do
    let(:comparator) { MermaidOutputComparator.new }
    let(:output) { capture { comparator.compare_type("flowchart") } }

    it "directs a missing-reference user to the existing rake task" do
      expect(output).to include("rake mermaid:generate_fixtures[flowchart]")
    end

    context "with an empty reference directory" do
      before { FileUtils.mkdir_p("spec/fixtures_mermaid/flowchart") }

      it "reports that no comparisons were performed" do
        expect(output).to include("No comparisons performed")
      end
    end

    context "with matching, different, broken, and unreferenced sources" do
      before do
        FileUtils.mkdir_p("spec/fixtures_mermaid/flowchart")
        %w[match different broken ignored].each do |name|
          seed_source(name, name)
        end
        %w[match different broken].each do |name|
          File.write("spec/fixtures_mermaid/flowchart/#{name}.svg", "<svg/>")
        end
        allow(Sirena).to receive(:render).with("match").and_return("<svg/>")
        allow(Sirena).to receive(:render).with("different")
          .and_return("<svg><path/><path/></svg>")
        allow(Sirena).to receive(:render).with("broken").and_raise("bad source")
      end

      it "counts failures and differences while skipping absent references" do
        expect(output).to include("1/3 similar (33.3%)", "2 differences")
      end
    end
  end

  context "when validating source outcomes" do
    let(:actual) do
      [MermaidTestValidator.name, MermaidTestValidator.new.validate_all]
    end

    before do
      stub_const("MermaidFixtureGenerator::DIAGRAM_TYPES", %w[flowchart empty])
      seed_source("valid", "valid")
      seed_source("broken", "broken")
      allow(Sirena).to receive(:render).with("valid").and_return("<svg/>")
      allow(Sirena).to receive(:render).with("broken")
        .and_raise("parse failure")
    end

    it "preserves the validator alias and per-type outcome counts" do
      expect(actual)
        .to eq(["MermaidTestValidator",
                { "flowchart" => { total: 2, passing: 1, failing: 1 },
                  "empty" => { total: 0, passing: 0, failing: 0 } }])
    end
  end

  context "when invoking the rake entry points" do
    let(:generator) { instance_spy(MermaidFixtureGenerator) }
    let(:comparator) { instance_spy(MermaidOutputComparator) }
    let(:references) { instance_double(MermaidReferenceGenerator) }
    let(:validator) { instance_double(MermaidTestValidator) }
    let(:status) { instance_double(Process::Status, success?: true) }

    before do
      allow(MermaidFixtureGenerator).to receive(:new).and_return(generator)
      allow(MermaidOutputComparator).to receive(:new).and_return(comparator)
      allow(MermaidReferenceGenerator).to receive(:new).and_return(references)
      allow(MermaidTestValidator).to receive(:new).and_return(validator)
      allow(MermaidToolchain).to receive_messages(verify_toolchain: true,
                                                  version_command: ["version"])
      allow(Open3).to receive(:capture2e).with("version")
        .and_return(["11.12.0\n", status])
    end

    def invoke_task(name, argument = nil)
      capture do
        task = Rake::Task["mermaid:#{name}"]
        task.reenable
        task.invoke(argument)
      end
    end

    it "dispatches default generation to every type after CLI verification" do
      invoke_task("generate_fixtures")
      expect(generator).to have_received(:generate_all_fixtures)
    end

    it "dispatches named generation to the supplied type" do
      invoke_task("generate_fixtures", "pie")
      expect(generator)
        .to have_received(:generate_fixtures_for_type).with("pie")
    end

    it "reports the successfully inspected pinned CLI version" do
      allow(generator).to receive(:generate_all_fixtures)

      expect(invoke_task("generate_fixtures"))
        .to include("Found pinned mermaid-cli: 11.12.0")
    end

    context "when CLI version inspection fails" do
      let(:status) { instance_double(Process::Status, success?: false) }

      it "preserves the version failure message" do
        expect { invoke_task("generate_fixtures") }
          .to raise_error(RuntimeError, "pinned mermaid-cli failed: 11.12.0\n")
      end
    end

    it "reports the number of newly generated references" do
      allow(references).to receive(:generate).and_return(%w[first second])

      expect(invoke_task("generate_missing_references"))
        .to eq("Generated 2 missing Mermaid reference(s)\n")
    end

    it "reports the verified reference count" do
      allow(references).to receive(:verify_provenance!).and_return(7)

      expect(invoke_task("check_reference_provenance"))
        .to eq("Verified 7 generated Mermaid reference(s)\n")
    end

    it "dispatches default comparison to all types" do
      invoke_task("compare")
      expect(comparator).to have_received(:compare_all_types)
    end

    it "dispatches named comparison to the supplied type" do
      invoke_task("compare", "pie")
      expect(comparator).to have_received(:compare_type).with("pie")
    end

    context "with mixed validator results" do
      before do
        allow(validator).to receive(:validate_all).and_return(
          "complete" => { passing: 2, total: 2 },
          "partial" => { passing: 1, total: 2 },
        )
      end

      it "prints per-type statuses and the weighted total" do
        report = invoke_task("validate")

        expect(report).to include("complete", "partial", "75.0%", "⚠️ ")
      end
    end
  end
end
