# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::StateDiagram do
  let(:connected_cases) do
    %w[
      state_diagram/mermaidapi_spec-5a5c8731.mmd
      state_diagram/mermaidapi_spec-c352a65c.mmd
      state_diagram/state-5753bc25.mmd
      state_diagram/state-c6b282f7.mmd
      state_diagram/statediagram_v2_spec-5f17d693.mmd
      unknown/statediagram_spec-9b9b640a.mmd
      unknown/statediagram_v2_spec-4d71f460.mmd
    ]
  end
  let(:nested_cases) do
    %w[
      state_diagram/should_handle_state_definitions_with_separation-a4e9be66.mmd
      state_diagram/should_handle_state_definitions_with_separation-cd10456b.mmd
      state_diagram/statediagram_spec-128d4533.mmd
      state_diagram/statediagram_spec-ac7e4b11.mmd
      state_diagram/statediagram_spec-f56a2ffc.mmd
      state_diagram/statediagram_v2_spec-2d12b6d7.mmd
    ]
  end

  def parity_rows(case_ids)
    runner = SpecSupport::LayoutParity::CohortRunner.new
    results = runner.comparison_cases.filter_map do |candidate|
      runner.send(:compare, candidate) if case_ids.include?(candidate.case_id)
    end
    SpecSupport::LayoutParity::CaseLedger.build(results)
  end

  def geometry_metrics(row)
    row.dig("summary", "metrics").values_at(
      "worst_e_c", "worst_e_w", "worst_e_h", "worst_e_a"
    )
  end

  it "places connected state chains within the geometry thresholds" do
    rows = parity_rows(connected_cases)

    expect(rows.map { |row| row.dig("summary", "hard_failure") }.uniq)
      .to eq([false])
    expect(rows.map { |row| geometry_metrics(row) }).to all(
      satisfy do |center, width, height, area|
        center <= 0.08 && [width, height, area].all? { |value| value <= 0.15 }
      end,
    )
  end

  it "matches plain nested-composite geometry in every duplicate row" do
    rows = parity_rows(nested_cases)

    expect(rows.map { |row| row.dig("summary", "hard_failure") }.uniq)
      .to eq([false])
    expect(rows.map { |row| geometry_metrics(row) })
      .to eq(Array.new(nested_cases.length) { [0.0, 0.0, 0.0, 0.0] })
  end
end
