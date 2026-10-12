# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::GitGraph, :aggregate_failures do
  def case_ids
    %w[
      gitgraph/gitgraph_spec-6dbfa6a3.mmd
      gitgraph/should_support_cherry_picking_commits-ecf31fda.mmd
      gitgraph/should_support_cherry_picking_commits_with_custo-7bafb75f.mmd
      gitgraph/should_support_cherry_picking_commits_with_no_ta-0234be84.mmd
      gitgraph/should_support_cherry_picking_of_merge_commits-e48959ff.mmd
      gitgraph/should_support_cherry_picking_of_merge_commits_w-29165ad9.mmd
      gitgraph/should_support_cherry_picking_of_merge_commits_w-670f4b6c.mmd
      gitgraph/should_support_cherry_picking_of_merge_commits_w-a7e851e5.mmd
    ]
  end

  def results
    runner = SpecSupport::LayoutParity::CohortRunner.new
    selected = runner.candidate_cases.select do |entry|
      case_ids.include?(entry.case_id)
    end
    selected.to_h { |entry| [entry.case_id, runner.send(:compare, entry)] }
  end

  def scene_for(source)
    diagram = Sirena::Parser::GitGraph.new.parse(source)
    described_class.new.call(diagram)
  end

  def parity_evidence
    [results.keys.sort, results.values.any?(&:hard_failure?),
     center_errors.max, residual_errors.uniq]
  end

  def center_errors
    results.values.map { |result| result.geometry.fetch(:worst_e_c) }
  end

  def residual_errors
    results.values.flat_map do |result|
      result.geometry.values_at(
        :worst_e_w, :worst_e_h, :worst_e_a, :worst_analog
      )
    end
  end

  let(:scene) do
    scene_for(<<~MERMAID)
      gitGraph
        commit id: "ZERO"
        branch develop
        commit id: "A"
        checkout main
        cherry-pick id: "A" tag: "picked"
    MERMAID
  end

  it "matches Mermaid's cherry-pick corpus geometry" do
    expect(parity_evidence)
      .to match([case_ids.sort, false, (be <= 0.08), [0.0]])
  end

  it "reserves horizontal branch-label clearance for cherry-pick graphs" do
    translations = scene.branches.map { |branch| branch.label.translation_x }

    expect(translations).to all(eq(-28.0))
  end

  it "anchors horizontal cherry-pick tags from their measured left edge" do
    cherry_pick = scene.commits.find(&:is_cherry_pick)
    label = cherry_pick.labels.fetch(0)

    expect([label.text_anchor, label.x < cherry_pick.x]).to eq(["start", true])
  end
end
