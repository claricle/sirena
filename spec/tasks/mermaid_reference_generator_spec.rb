# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "json"
require "rake"
require "tmpdir"

load File.expand_path("../../tasks/generate_mermaid_fixtures.rake", __dir__)

RSpec.describe MermaidReferenceGenerator do
  subject(:generator) do
    described_class.new(root: root, toolchain: toolchain, runner: runner,
                        detector: detector, canary: -> { true })
  end

  let(:root) { Dir.mktmpdir }
  let(:toolchain) { class_double(MermaidToolchain) }
  let(:runner) { class_double(HardenedMmdc) }
  let(:detector) { ->(source) { source.lines.first.strip.to_sym } }
  let(:target_paths) do
    %w[spec/fixtures_mermaid/class_diagram/class_case.svg
       spec/fixtures_mermaid/er_diagram/er_case.svg
       spec/fixtures_mermaid/flowchart/flowchart_case.svg
       spec/fixtures_mermaid/gantt/gantt_case.svg
       spec/fixtures_mermaid/gitgraph/git_case.svg]
  end

  before do
    FileUtils.mkdir_p(File.join(root, "scoreboard"))
    allow(toolchain).to receive(:verify_toolchain).and_return(
      "mmdc" => "11.12.0", "mermaid" => "11.16.1",
    )
    allow(toolchain).to receive(:command) { |*args| ["mmdc", *args] }
    allow(runner).to receive(:run_mmdc) do |_input, output|
      File.write(output, '<svg aria-roledescription="gitGraph"/>')
      [instance_double(Process::Status, success?: true), ""]
    end
  end

  after { FileUtils.remove_entry(root) }

  it "generates every missing target in its canonical reference directory" do
    seed_targets
    references = generator.generate

    expect(references.map { |entry| relative(entry.reference_path) })
      .to eq(target_paths)
  end

  it "records source, toolchain, command, output, and unknown upstream SHA" do
    seed_case("git/case.mmd", "git_graph\nbody\n")
    generator.generate

    expect(provenance_summary).to eq(
      ["11.12.0", nil, described_class::UNKNOWN_UPSTREAM, true, true, true],
    )
  end

  it "refuses colliding reference names with different source bytes" do
    seed_case("git/same.mmd", "git_graph\none\n")
    seed_case("unknown/same.mmd", "git_graph\ntwo\n")

    expect { generator.generate }.to raise_error(
      described_class::ConflictError, /git\/same.*unknown\/same/
    )
  end

  it "reuses an agreeing reference for a byte-identical corpus twin" do
    seed_case("gitgraph/owner.mmd", "git_graph\nsame\n")
    seed_case("git/duplicate.mmd", "git_graph\nsame\n")
    write_reference("gitgraph/owner.svg", "<svg/>")

    expect(generator.missing_references).to be_empty
  end

  it "generates instead of selecting conflicting duplicate references" do
    seed_conflicting_twins

    expect(generator.missing_references.map(&:cases))
      .to eq([["git/missing.mmd"]])
  end

  it "removes partial output when pinned generation fails" do
    seed_case("gantt/broken.mmd", "gantt\nbody\n")
    allow(runner).to receive(:run_mmdc).and_return([nil, "browser crashed"])

    expect_generation_failure
  end

  it "verifies committed source and output checksums" do
    seed_case("class_diagram/case.mmd", "class_diagram\nbody\n")
    generator.generate
    File.write(reference_files.fetch(0), "changed")

    expect { generator.verify_provenance! }.to raise_error(/output checksum/)
  end

  def seed_targets
    seed_case("class_diagram/class_case.mmd", "class_diagram\nbody\n")
    seed_case("er/er_case.mmd", "er_diagram\nbody\n")
    seed_case("unknown/flowchart_case.mmd", "flowchart\nbody\n")
    seed_case("gantt/gantt_case.mmd", "gantt\nbody\n")
    seed_case("git/git_case.mmd", "git_graph\nbody\n")
    seed_case("pie/ignored.mmd", "pie\nbody\n")
  end

  def seed_conflicting_twins
    source = "git_graph\nsame\n"
    seed_case("gitgraph/first.mmd", source)
    seed_case("unknown/second.mmd", source)
    seed_case("git/missing.mmd", source)
    write_reference("gitgraph/first.svg", "<svg id=\"first\"/>")
    write_reference("gitgraph/second.svg", "<svg id=\"second\"/>")
  end

  def seed_case(case_id, source)
    path = File.join(root, "spec", "mermaid", case_id)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, source)
    write_metadata(path, case_id)
    write_corpus_row(case_id)
  end

  def write_metadata(path, case_id)
    metadata = { "source_file" => "/upstream/#{case_id}", "line_number" => 7 }
    File.write(path.sub(/\.mmd\z/, ".meta.json"), JSON.generate(metadata))
  end

  def write_corpus_row(case_id)
    rows << { "case" => case_id, "verdict" => "valid", "pass" => true }
    path = File.join(root, "scoreboard", "corpus.json")
    File.write(path, JSON.generate(rows))
  end

  def rows
    @rows ||= []
  end

  def reference_files
    Dir.glob(File.join(root, "spec", "fixtures_mermaid", "**", "*.svg"))
  end

  def write_reference(relative_path, contents)
    path = File.join(root, "spec", "fixtures_mermaid", relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, contents)
  end

  def provenance_summary
    path = File.join(root, "spec", "fixtures_mermaid",
                     "reference-provenance.json")
    payload = JSON.parse(File.read(path))
    provenance_values(payload, payload.fetch("references").fetch(0))
  end

  def provenance_values(payload, record)
    [payload.dig("toolchain", "mmdc"), record["upstream_sha"],
     record.fetch("upstream_sha_status"), !record.fetch("command").empty?,
     record.fetch("source_sha256").length == 64,
     record.fetch("output_sha256").length == 64]
  end

  def expect_generation_failure
    expect { generator.generate }.to raise_error(/browser crashed/)
    expect(reference_files).to be_empty
  end

  def relative(path)
    path.delete_prefix("#{root}/")
  end
end
