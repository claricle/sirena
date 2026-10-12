# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::GitGraph, :aggregate_failures do
  def case_ids
    %w[
      gitgraph/gitgraph_spec-6422a3f5.mmd
      gitgraph/gitgraph_spec-72370fac.mmd
      gitgraph/gitgraph_spec-85c9fffd.mmd
      gitgraph/gitgraph_spec-88f6da03.mmd
      gitgraph/gitgraph_spec-8a6b8cc3.mmd
      gitgraph/gitgraph_spec-8ec1ba43.mmd
      gitgraph/gitgraph_spec-a2c9fdfa.mmd
      gitgraph/gitgraph_spec-efafa38a.mmd
      gitgraph/gitgraph_spec-f2a04b5e.mmd
      gitgraph/gitgraph_spec-f45d7013.mmd
      gitgraph/gitgraph_spec-ff5daf60.mmd
    ]
  end

  def results
    runner = SpecSupport::LayoutParity::CohortRunner.new
    selected = runner.candidate_cases.select do |entry|
      case_ids.include?(entry.case_id)
    end
    selected.to_h { |entry| [entry.case_id, runner.send(:compare, entry)] }
  end

  it "rotates every vertical commit ID like Mermaid" do
    expect(results.keys).to match_array(case_ids)
    results.each_value do |result|
      expect(result).not_to be_hard_failure
      expect(result.geometry.fetch(:worst_e_c)).to be <= 0.08
    end
  end
end
