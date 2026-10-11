# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::GitGraph, :aggregate_failures do
  def case_ids
    %w[
      gitgraph/appli_spec-9896cabe.mmd
      gitgraph/gitgraph_spec-2624f69c.mmd
      gitgraph/gitgraph_spec-28053fe8.mmd
      gitgraph/gitgraph_spec-4ecf8c56.mmd
      gitgraph/gitgraph_spec-b81d6654.mmd
      gitgraph/gitgraph_spec-e1c6c758.mmd
      gitgraph/gitgraph_spec-fdc1c9db.mmd
      gitgraph/should_handle_3_straight_commits-a0c3914d.mmd
    ]
  end

  def results
    runner = SpecSupport::LayoutParity::CohortRunner.new
    selected = runner.candidate_cases.select do |entry|
      case_ids.include?(entry.case_id)
    end
    selected.to_h { |entry| [entry.case_id, runner.send(:compare, entry)] }
  end

  it "matches Mermaid's three-commit linear geometry in every direction" do
    expect(results.keys).to match_array(case_ids)
    results.each_value do |result|
      expect(result).not_to be_hard_failure
      expect(result.geometry.fetch(:worst_e_c)).to be <= 0.08
    end
  end
end
