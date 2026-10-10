# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::StateDiagram do
  include SpecSupport::LayoutParity::FigureHelpers

  let(:note_cases) do
    %w[
      state/027_parser_should_handle_multiline_notes_with_different_line_breaks_26.mmd
      state/051_parser_should_handle_multiline_notes_with_different_line_breaks_50.mmd
      state_diagram/026_parser_should_handle_multiline_notes_with_different_line_breaks_25.mmd
      state_diagram/049_parser_should_handle_multiline_notes_with_different_line_breaks_48.mmd
      state_diagram/050_parser_should_handle_multiline_notes_with_different_line_breaks_49.mmd
      state_diagram/073_parser_should_handle_multiline_notes_with_different_line_breaks_72.mmd
      state_diagram/097_parser_should_handle_multiline_notes_with_different_line_breaks_96.mmd
    ]
  end
  let(:control_cases) do
    %w[
      state/020_parser_should_handle_state_definitions_with_separation_of_id_19.mmd
      state/030_parser_should_handle_notes_for_composite_nested_states_29.mmd
      state/044_parser_should_handle_state_definitions_with_separation_of_id_43.mmd
      state_diagram/019_parser_should_handle_state_definitions_with_separation_of_id_18.mmd
      state_diagram/029_parser_should_handle_notes_for_composite_nested_states_28.mmd
      state_diagram/043_parser_should_handle_state_definitions_with_separation_of_id_42.mmd
      state_diagram/052_parser_should_handle_notes_for_composite_nested_states_51.mmd
      state_diagram/066_parser_should_handle_state_definitions_with_separation_of_id_65.mmd
      state_diagram/090_parser_should_handle_state_definitions_with_separation_of_id_89.mmd
    ]
  end

  def source
    File.read("spec/mermaid/#{note_cases.first}")
  end

  def note_evidence
    diagram = Sirena::Parser::StateDiagram.new.parse(source)
    scene = described_class.new.scene(diagram)
    note = scene.children.find { |node| node.id == "State1----note" }
    figure = extract(Sirena.render(source), state_recognizer)
    [diagram.notes.map { |item| [item.target_id, item.position] },
     note.labels.map(&:text), figure.elements.map(&:key)]
  end

  def state_recognizer
    SpecSupport::LayoutParity::StateDiagramRecognizer.new
  end

  def fresh_rows
    cases = note_cases + control_cases
    runner = SpecSupport::LayoutParity::CohortRunner.new
    results = runner.comparison_cases.filter_map do |candidate|
      runner.send(:compare, candidate) if cases.include?(candidate.case_id)
    end
    SpecSupport::LayoutParity::CaseLedger.build(results)
  end

  def committed_rows
    path = File.join(SpecSupport::LayoutParity::CohortRunner::ROOT,
                     "scoreboard/layout-parity.json")
    JSON.parse(File.read(path)).select do |row|
      (note_cases + control_cases).include?(row.fetch("case"))
    end
  end

  it "preserves attached multiline notes through the rendered figure" do
    expect(note_evidence).to eq(
      [[%w[State1 right]], %w[Line1 Line2 Line3 Line4 Line5],
       %w[State1 State1----note]],
    )
  end

  it "recovers multiline notes without regressing State controls" do
    rows = fresh_rows
    fixed = rows.select { |row| note_cases.include?(row.fetch("case")) }
    diff = SpecSupport::LayoutParity::ScoreboardRatchet.diff(
      committed: committed_rows, fresh: rows,
    )
    expect([fixed.map { |row| row.dig("summary", "hard_failure") }.uniq,
            diff[:regressions]]).to eq([[false], []])
  end
end
