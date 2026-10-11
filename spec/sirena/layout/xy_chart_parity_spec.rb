# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::XyChart do
  let(:case_id) { "xychart/001_example_xychart_0.mmd" }
  let(:runner) { SpecSupport::LayoutParity::CohortRunner.new }

  def parity_result
    candidate = runner.candidate_cases.find { |item| item.case_id == case_id }
    runner.send(:compare, candidate)
  end

  def parity_summary
    result = parity_result
    geometry = result.geometry
    metrics = geometry.values_at(:worst_e_c, :worst_e_w,
                                 :worst_e_h, :worst_e_a)
    [geometry.fetch(:matched), result.invariants, metrics]
  end

  it "meets the geometry contract for every recognized series mark" do
    expect(parity_summary).to match(
      [13, [], Array.new(4) { be <= 0.001 }],
    )
  end
end
