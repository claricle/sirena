# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::StateDiagram do
  include SpecSupport::LayoutParity::FigureHelpers

  let(:note_cases) do
    [
      multiline_note_case("state", 27, 26),
      multiline_note_case("state", 51, 50),
      multiline_note_case("state_diagram", 26, 25),
      multiline_note_case("state_diagram", 49, 48),
      multiline_note_case("state_diagram", 50, 49),
      multiline_note_case("state_diagram", 73, 72),
      multiline_note_case("state_diagram", 97, 96),
    ]
  end
  let(:control_cases) do
    [
      separation_case("state", 20, 19),
      composite_note_case("state", 30, 29),
      separation_case("state", 44, 43),
      separation_case("state_diagram", 19, 18),
      composite_note_case("state_diagram", 29, 28),
      separation_case("state_diagram", 43, 42),
      composite_note_case("state_diagram", 52, 51),
      separation_case("state_diagram", 66, 65),
      separation_case("state_diagram", 90, 89),
    ]
  end

  def multiline_note_case(directory, number, source_number)
    "#{directory}/#{format('%03d', number)}_parser_should_handle_multiline_" \
      "notes_with_different_line_breaks_#{source_number}.mmd"
  end

  def separation_case(directory, number, source_number)
    "#{directory}/#{format('%03d', number)}_parser_should_handle_state_" \
      "definitions_with_separation_of_id_#{source_number}.mmd"
  end

  def composite_note_case(directory, number, source_number)
    "#{directory}/#{format('%03d', number)}_parser_should_handle_notes_for_" \
      "composite_nested_states_#{source_number}.mmd"
  end

  def source
    File.read("spec/mermaid/#{note_cases.first}")
  end

  def note_evidence
    diagram = Sirena::Parser::StateDiagram.new.parse(source)
    [note_metadata(diagram), rendered_note_labels(diagram), recognized_keys]
  end

  def note_metadata(diagram)
    diagram.notes.map { |item| [item.target_id, item.position] }
  end

  def rendered_note_labels(diagram)
    scene = described_class.new.scene(diagram)
    note = scene.children.find { |node| node.id == "State1----note" }
    note.labels.map(&:text)
  end

  def recognized_keys
    figure = extract(Sirena.render(source), state_recognizer)
    figure.elements.map(&:key)
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

  def expected_note_evidence
    [[%w[State1 right]], %w[Line1 Line2 Line3 Line4 Line5],
     %w[State1 State1----note]]
  end

  def fixed_hard_failures(rows)
    fixed = rows.select { |row| note_cases.include?(row.fetch("case")) }
    fixed.map { |row| row.dig("summary", "hard_failure") }.uniq
  end

  def regressions_for(rows)
    SpecSupport::LayoutParity::ScoreboardRatchet.diff(
      committed: committed_rows, fresh: rows,
    )[:regressions]
  end

  def parity_evidence
    rows = fresh_rows
    [fixed_hard_failures(rows), regressions_for(rows)]
  end

  it "preserves attached multiline notes through the rendered figure" do
    expect(note_evidence).to eq(expected_note_evidence)
  end

  it "recovers multiline notes without regressing State controls" do
    expect(parity_evidence).to eq([[false], []])
  end
end
