# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Timeline do
  let(:case_id) do
    "timeline/should_handle_a_section_and_task_and_its_events-1afb897a.mmd"
  end
  let(:result) { parity_result }
  let(:geometry) { result.geometry }
  let(:metrics) do
    geometry.values_at(:worst_e_c, :worst_e_w, :worst_e_h, :worst_e_a)
  end

  def parity_result
    runner = SpecSupport::LayoutParity::CohortRunner.new
    candidate = runner.comparison_cases.find { |item| item.case_id == case_id }
    runner.send(:compare, candidate)
  end

  it "measures the long event label at Mermaid's browser width" do
    width = Sirena::Layout::TimelineText.width_of(
      "[event1](http://example.com)",
    )

    expect(width).to eq(221.71875)
  end

  it "matches every recognized element within subpixel precision" do
    expect([geometry.fetch(:matched), result.invariants, metrics]).to match(
      [7, [], Array.new(4) { be <= 0.0000001 }],
    )
  end
end
