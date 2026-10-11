# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::StateDiagram do
  include SpecSupport::LayoutParity::FigureHelpers

  let(:source) do
    File.read(
      "spec/mermaid/state_diagram/" \
      "should_handle_state_definitions_with_separation-cd10456b.mmd",
    )
  end
  let(:separation_cases) do
    %w[
      state_diagram/should_handle_state_definitions_with_separation-cd10456b
      state_diagram/should_handle_state_definitions_with_separation-a4e9be66
      state_diagram/statediagram_v2_spec-2d12b6d7
      state_diagram/statediagram_spec-f56a2ffc
      state_diagram/statediagram_spec-ac7e4b11
      state_diagram/statediagram_spec-128d4533
    ].map { |id| "#{id}.mmd" }
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
    runner = SpecSupport::LayoutParity::CohortRunner.new
    results = runner.candidate_cases.filter_map do |candidate|
      if separation_cases.include?(candidate.case_id)
        runner.send(:compare, candidate)
      end
    end
    SpecSupport::LayoutParity::CaseLedger.build(results)
  end

  def committed_rows
    path = File.join(SpecSupport::LayoutParity::CohortRunner::ROOT,
                     "scoreboard/layout-parity.json")
    JSON.parse(File.read(path)).select do |row|
      separation_cases.include?(row.fetch("case"))
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
