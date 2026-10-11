# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::ClassDiagram do
  let(:case_ids) do
    %w[
      class_diagram/classdiagram_elk_v3_spec-d813b31f.mmd
      class_diagram/classdiagram_handdrawn_v3_spec-9be2f114.mmd
      class_diagram/classdiagram_v2_spec-9f6f35ba.mmd
      class_diagram/classdiagram_v3_spec-57b031e5.mmd
    ]
  end

  let(:results) do
    runner = SpecSupport::LayoutParity::CohortRunner.new
    candidates = runner.candidate_cases.select do |candidate|
      case_ids.include?(candidate.case_id)
    end
    candidates.map { |candidate| runner.send(:compare, candidate) }
  end

  it "compares the Animal/Duck alias case in every corpus copy" do
    expect(results.map(&:case_id)).to match_array(case_ids)
  end

  it "has no hard failure in any corpus copy of the Animal/Duck case" do
    results.each do |result|
      expect(result).not_to be_hard_failure, result.case_id
    end
  end

  it "matches the Animal/Duck alias placement in every corpus copy",
     :aggregate_failures do
    results.each do |result|
      expect(result.geometry.fetch(:worst_e_c)).to be <= 0.08, result.case_id
      expect(result.geometry.fetch(:worst_e_w)).to be <= 0.15, result.case_id
      expect(result.geometry.fetch(:worst_e_h)).to be <= 0.15, result.case_id
    end
  end
end
