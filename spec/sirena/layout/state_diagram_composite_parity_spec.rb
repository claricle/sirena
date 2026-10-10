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
    %w[
      state/020_parser_should_handle_state_definitions_with_separation_of_id_19.mmd
      state/044_parser_should_handle_state_definitions_with_separation_of_id_43.mmd
      state_diagram/019_parser_should_handle_state_definitions_with_separation_of_id_18.mmd
      state_diagram/043_parser_should_handle_state_definitions_with_separation_of_id_42.mmd
      state_diagram/066_parser_should_handle_state_definitions_with_separation_of_id_65.mmd
      state_diagram/090_parser_should_handle_state_definitions_with_separation_of_id_89.mmd
    ]
  end
  let(:composite_note_cases) do
    %w[
      state/030_parser_should_handle_notes_for_composite_nested_states_29.mmd
      state_diagram/029_parser_should_handle_notes_for_composite_nested_states_28.mmd
      state_diagram/052_parser_should_handle_notes_for_composite_nested_states_51.mmd
    ]
  end

  def hierarchy_evidence
    diagram = Sirena::Parser::StateDiagram.new.parse(source)
    scene = described_class.new.scene(diagram)
    figure = extract(Sirena.render(source), state_recognizer)
    [diagram.states.map(&:id), diagram.find_state("Idle").id,
     diagram.states.first.children.map(&:id),
     scene.children.first.children.map(&:id), parents_of(figure)]
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

  it "preserves composite ownership through the rendered figure" do
    expect(hierarchy_evidence).to eq(
      [["NotShooting"], "Idle", %w[Idle Configuring start_1],
       %w[Idle Configuring start_1],
       { "NotShooting" => nil, "Idle" => "NotShooting",
         "[*]" => "NotShooting", "Configuring" => "NotShooting" }],
    )
  end

  it "removes separation failures without regressing composite cases" do
    rows = parity_rows
    fixed = rows.select { |row| separation_cases.include?(row.fetch("case")) }
    diff = SpecSupport::LayoutParity::ScoreboardRatchet.diff(
      committed: committed_rows, fresh: rows,
    )
    expect([fixed.map { |row| row.dig("summary", "hard_failure") }.uniq,
            diff[:regressions]]).to eq([[false], []])
  end
end
