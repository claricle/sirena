# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::GitGraph, :aggregate_failures do
  def case_ids
    %w[
      gitgraph/gitgraph_spec-0b6593b9.mmd
      gitgraph/gitgraph_spec-10b01f23.mmd
      gitgraph/gitgraph_spec-114a946d.mmd
      gitgraph/gitgraph_spec-44d278b2.mmd
      gitgraph/gitgraph_spec-5ec00071.mmd
      gitgraph/gitgraph_spec-85d8094a.mmd
      gitgraph/gitgraph_spec-a3fd0bd6.mmd
      gitgraph/gitgraph_spec-fbfbfcbd.mmd
    ]
  end

  def results
    runner = SpecSupport::LayoutParity::CohortRunner.new
    selected = runner.candidate_cases.select do |entry|
      case_ids.include?(entry.case_id)
    end
    selected.to_h { |entry| [entry.case_id, runner.send(:compare, entry)] }
  end

  it "matches Mermaid's ordinary explicit-ID branch-label clearance" do
    expect(results.keys).to match_array(case_ids)
    results.each_value do |result|
      expect(result).not_to be_hard_failure
      expect(result.geometry.fetch(:worst_e_c)).to be <= 0.08
    end
  end
end
