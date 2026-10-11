# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::StateDiagram do
  include SpecSupport::LayoutParity::FigureHelpers

  let(:note_cases) do
    %w[
      state_diagram/should_handle_multiline_notes_with_different_lin-b6ac271b
      state_diagram/should_handle_multiline_notes_with_different_lin-90d75e03
      state_diagram/statediagram_v2_spec-6aad18a9
      state_diagram/statediagram_v2_spec-9dfc4ef4
      state_diagram/statediagram_spec-bdd17264
      state_diagram/statediagram_spec-1acdbd7b
      state_diagram/statediagram_spec-3fdaec54
    ].map { |id| "#{id}.mmd" }
  end
  let(:control_cases) do
    %w[
      state_diagram/should_handle_state_definitions_with_separation-cd10456b
      state_diagram/should_handle_state_definitions_with_separation-a4e9be66
      state_diagram/statediagram_v2_spec-2d12b6d7
      state_diagram/statediagram_spec-f56a2ffc
      state_diagram/statediagram_spec-ac7e4b11
      state_diagram/statediagram_spec-128d4533
    ].map { |id| "#{id}.mmd" }
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
