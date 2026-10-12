# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::GitGraph, :aggregate_failures do
  let(:vertical_scene) do
    scene_for(<<~MERMAID)
      gitGraph TB:
        commit id: "one"
        branch short
        commit id: "two"
        branch a_much_longer_branch
        commit id: "three"
    MERMAID
  end
  let(:mixed_order_scene) do
    scene_for(<<~MERMAID)
      gitGraph
        commit
        branch test1 order: 1
        branch test2
        branch test3
    MERMAID
  end

  def case_ids
    %w[
      gitgraph/gitgraph_spec-076af5a8.mmd
      gitgraph/gitgraph_spec-27965d7e.mmd
      gitgraph/gitgraph_spec-2a707d2a.mmd
      gitgraph/gitgraph_spec-7601eeee.mmd
      gitgraph/gitgraph_spec-7d932392.mmd
      gitgraph/gitgraph_spec-87a15537.mmd
      gitgraph/gitgraph_spec-b187a403.mmd
      gitgraph/gitgraph_spec-b766651e.mmd
      gitgraph/gitgraph_spec-d0791e6a.mmd
      gitgraph/gitgraph_spec-ecc8f1ae.mmd
      gitgraph/should_handle_new_branch_checkout_with_and_witho-322aea60.mmd
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
     center_errors.max, residual_errors.max]
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

  def vertical_gaps(scene)
    centers = scene.commits.group_by(&:lane)
      .sort.map { |_lane, commits| commits.first.x }
    centers.each_cons(2).map { |left, right| right - left }
  end

  it "matches Mermaid's measured vertical lanes and mixed branch order" do
    expect(parity_evidence)
      .to match([case_ids.sort, false, (be <= 0.08), (be <= 0.000000000001)])
  end

  it "adds prior-label width to each following vertical lane" do
    gaps = vertical_gaps(vertical_scene)
    expect(gaps.fetch(1)).to be > gaps.fetch(0)
  end

  it "places implicit branches before explicitly ordered branches" do
    lanes = mixed_order_scene.branches.to_h do |branch|
      [branch.name, branch.lane]
    end
    expect(lanes)
      .to include("test2" => 1, "test3" => 2, "test1" => 3)
  end
end
