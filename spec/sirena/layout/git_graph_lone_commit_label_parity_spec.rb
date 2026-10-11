# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::GitGraph, :aggregate_failures do
  def case_ids
    %w[
      gitgraph/should_handle_a_gitgraph_commit_with_custom_comm-319cfc9c.mmd
      gitgraph/should_handle_a_gitgraph_commit_with_custom_comm-3a7948d6.mmd
      gitgraph/should_handle_a_gitgraph_commit_with_custom_comm-4fcb935d.mmd
      gitgraph/should_handle_a_gitgraph_commit_with_custom_comm-5f8425ba.mmd
      gitgraph/should_handle_a_gitgraph_commit_with_custom_comm-dc4a307a.mmd
      gitgraph/should_handle_a_gitgraph_commit_with_custom_comm-e548d918.mmd
      gitgraph/should_handle_a_gitgraph_commit_with_custom_msg-1e0c305c.mmd
      gitgraph/should_handle_a_gitgraph_commit_with_custom_tag-f23d9a2b.mmd
      gitgraph/should_handle_a_gitgraph_commit_with_custom_type-bce4b490.mmd
    ]
  end

  def results
    runner = SpecSupport::LayoutParity::CohortRunner.new
    selected = runner.candidate_cases.select do |entry|
      case_ids.include?(entry.case_id)
    end
    selected.to_h { |entry| [entry.case_id, runner.send(:compare, entry)] }
  end

  it "matches Mermaid's lone-commit label geometry" do
    expect(results.keys).to match_array(case_ids)
    results.each_value do |result|
      expect(result).not_to be_hard_failure
      expect(result.geometry.fetch(:worst_e_c)).to be <= 0.08
    end
  end
end
