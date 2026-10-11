# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::StateDiagram do
  include SpecSupport::LayoutParity::FigureHelpers

  let(:source) do
    File.read(
      "spec/mermaid/state/020_parser_should_handle_state_definitions_with_" \
      "separation_of_id_19.mmd",
    )
  end
  let(:separation_cases) do
    [
      separation_case("state", 20, 19),
      separation_case("state", 44, 43),
      separation_case("state_diagram", 19, 18),
      separation_case("state_diagram", 43, 42),
      separation_case("state_diagram", 66, 65),
      separation_case("state_diagram", 90, 89),
    ]
  end
  let(:composite_note_cases) do
    [
      composite_note_case("state", 30, 29),
      composite_note_case("state_diagram", 29, 28),
      composite_note_case("state_diagram", 52, 51),
    ]
  end

  def separation_case(directory, number, source_number)
    "#{directory}/#{format('%03d', number)}_parser_should_handle_state_" \
      "definitions_with_separation_of_id_#{source_number}.mmd"
  end

  def composite_note_case(directory, number, source_number)
    "#{directory}/#{format('%03d', number)}_parser_should_handle_notes_for_" \
      "composite_nested_states_#{source_number}.mmd"
  end

  def hierarchy_evidence
    diagram = Sirena::Parser::StateDiagram.new.parse(source)
    model_hierarchy(diagram) + rendered_hierarchy(diagram)
  end

  def model_hierarchy(diagram)
    [diagram.states.map(&:id), diagram.find_state("Idle").id,
     diagram.states.first.children.map(&:id)]
  end

  def rendered_hierarchy(diagram)
    scene = described_class.new.scene(diagram)
    figure = extract(Sirena.render(source), state_recognizer)
    [scene.children.first.children.map(&:id), parents_of(figure)]
  end

  def state_recognizer
    SpecSupport::LayoutParity::StateDiagramRecognizer.new
  end

  def parity_rows
    cases = separation_cases + composite_note_cases
    runner = SpecSupport::LayoutParity::CohortRunner.new
    results = runner.candidate_cases.filter_map do |candidate|
      runner.send(:compare, candidate) if cases.include?(candidate.case_id)
    end
    SpecSupport::LayoutParity::CaseLedger.build(results)
  end

  def committed_rows
    path = File.join(SpecSupport::LayoutParity::CohortRunner::ROOT,
                     "scoreboard/layout-parity.json")
    JSON.parse(File.read(path)).select do |row|
      (separation_cases + composite_note_cases).include?(row.fetch("case"))
    end
  end

  def expected_hierarchy
    [["NotShooting"], "Idle", %w[Idle Configuring start_1],
     %w[Idle Configuring start_1],
     { "NotShooting" => nil, "Idle" => "NotShooting",
       "[*]" => "NotShooting", "Configuring" => "NotShooting" }]
  end

  def parity_evidence
    rows = parity_rows
    fixed = rows.select { |row| separation_cases.include?(row.fetch("case")) }
    diff = SpecSupport::LayoutParity::ScoreboardRatchet.diff(
      committed: committed_rows, fresh: rows,
    )
    [fixed.map { |row| row.dig("summary", "hard_failure") }.uniq,
     diff[:regressions]]
  end

  it "preserves composite ownership through the rendered figure" do
    expect(hierarchy_evidence).to eq(expected_hierarchy)
  end

  it "removes separation failures without regressing composite cases" do
    expect(parity_evidence).to eq([[false], []])
  end
end
