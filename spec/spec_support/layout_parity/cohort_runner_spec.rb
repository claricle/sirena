# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "json"
require "tmpdir"

RSpec.describe SpecSupport::LayoutParity::CohortRunner do
  subject(:results) { runner.run }

  let(:paths) do
    root = Dir.mktmpdir
    {
      root: root,
      scoreboard: File.join(root, "scoreboard.json"),
      corpus: File.join(root, "corpus"),
      references: File.join(root, "references"),
    }
  end
  let(:comparator) { class_double(SpecSupport::LayoutParity::CaseComparator) }
  let(:renderer) { instance_double(Sirena::Engine) }
  let(:captured_arguments) { [] }
  let(:runner) do
    described_class.new(
      paths: paths.slice(:scoreboard, :corpus, :references),
      comparator: comparator,
      renderer: renderer,
      detector: Sirena::Notation::Mermaid.method(:detect_type),
    )
  end

  before do
    FileUtils.mkdir_p(paths.fetch(:corpus))
    FileUtils.mkdir_p(paths.fetch(:references))
    allow(comparator).to receive(:compare) do |**arguments|
      captured_arguments << arguments
      :compared
    end
  end

  after { FileUtils.remove_entry(paths.fetch(:root)) }

  it "partitions candidates into the cohort and completeness failures" do
    seed_partition

    expect(partitioned_case_ids).to eq(
      [%w[flowchart/kept.mmd flowchart/missing.mmd],
       ["flowchart/kept.mmd"], ["flowchart/missing.mmd"]],
    )
  end

  it "resolves duplicate corpus directories through the reference directory" do
    reference_path = seed_alias_case
    results
    expect(argument_summary).to eq(alias_summary(reference_path))
  end

  it "detects the real Mermaid type for an unknown-directory case" do
    seed_unknown_case
    results
    expect(type_summary).to eq(
      ["git_graph", SpecSupport::LayoutParity::GitGraphRecognizer],
    )
  end

  it "sends a missing reference to the comparator as a hard-failure input" do
    seed_missing_case
    results
    expect(missing_summary).to eq(
      ["spec/fixtures_mermaid/flowchart/missing.svg", nil, nil],
    )
  end

  it "records a candidate render failure with its pipeline stage" do
    seed_render_failure
    results
    expect(render_failure_summary).to eq(expected_render_failure)
  end

  def seed_partition
    %w[kept missing invalid failing].each do |name|
      write_case("flowchart/#{name}.mmd", "flowchart LR\n#{name}")
    end
    write_scoreboard(row("flowchart/kept.mmd"),
                     row("flowchart/missing.mmd"),
                     row("flowchart/invalid.mmd", verdict: "invalid"),
                     row("flowchart/failing.mmd", pass: false))
    write_reference("flowchart/kept.svg")
  end

  def partitioned_case_ids
    [runner.candidate_cases, runner.comparison_cases,
     runner.missing_reference_cases].map { |cases| cases.map(&:case_id) }
  end

  def seed_alias_case
    source = "classDiagram\nclass A"
    write_case("class_diagram/example.mmd", source)
    write_scoreboard(row("class_diagram/example.mmd"))
    reference_path = write_reference("class/example.svg")
    allow(renderer).to receive(:render).with(source).and_return(candidate_svg)
    reference_path
  end

  def alias_summary(reference_path)
    ["class_diagram", "spec/fixtures_mermaid/class/example.svg",
     File.read(reference_path),
     SpecSupport::LayoutParity::ClassDiagramRecognizer]
  end

  def seed_unknown_case
    source = "gitGraph\n  commit"
    write_case("unknown/example.mmd", source)
    write_scoreboard(row("unknown/example.mmd"))
    write_reference("gitgraph/example.svg")
    allow(renderer).to receive(:render).with(source).and_return(candidate_svg)
  end

  def type_summary
    arguments = captured_arguments.fetch(0)
    [arguments[:type], arguments[:recognizer].class]
  end

  def seed_missing_case
    write_case("flowchart/missing.mmd", "flowchart LR\nA")
    write_scoreboard(row("flowchart/missing.mmd"))
    allow(renderer).to receive(:render) { raise "missing case was rendered" }
  end

  def missing_summary
    captured_arguments.fetch(0)
      .values_at(:reference, :reference_svg, :sirena_svg)
  end

  def seed_render_failure
    source = "flowchart LR\nA"
    write_case("flowchart/broken.mmd", source)
    write_scoreboard(row("flowchart/broken.mmd"))
    write_reference("flowchart/broken.svg")
    allow(renderer).to receive(:render).with(source)
      .and_raise(Sirena::Layout::LayoutError, "cannot place")
  end

  def render_failure_summary
    arguments = captured_arguments.fetch(0)
    [arguments[:sirena_svg], arguments[:render_error]]
  end

  def expected_render_failure
    [nil, { error_stage: "layout",
            exception_class: "Sirena::Layout::LayoutError",
            message: "cannot place" }]
  end

  def argument_summary
    arguments = captured_arguments.fetch(0)
    arguments.values_at(:type, :reference, :reference_svg) +
      [arguments[:recognizer].class]
  end

  def candidate_svg
    '<svg viewBox="0 0 1 1"/>'
  end

  def row(case_id, verdict: "valid", pass: true)
    { "case" => case_id, "verdict" => verdict, "pass" => pass }
  end

  def write_scoreboard(*rows)
    File.write(paths.fetch(:scoreboard), JSON.generate(rows))
  end

  def write_case(relative_path, source)
    path = File.join(paths.fetch(:corpus), relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, source)
  end

  def write_reference(relative_path)
    path = File.join(paths.fetch(:references), relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, '<svg viewBox="0 0 1 1"/>')
    path
  end
end
