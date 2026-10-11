# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::StateDiagram do
  let(:case_id) do
    "state_diagram/statediagram_v2_spec-c351b77a.mmd"
  end

  let(:row) { parity_row }
  let(:metrics) do
    row.dig("summary", "metrics").values_at(
      "worst_e_c", "worst_e_w", "worst_e_h", "worst_e_a"
    )
  end

  def parity_row
    runner = SpecSupport::LayoutParity::CohortRunner.new
    candidate = runner.candidate_cases.find do |entry|
      entry.case_id == case_id
    end
    result = runner.send(:compare, candidate)
    SpecSupport::LayoutParity::CaseLedger.build([result]).first
  end

  it "matches the concurrent-region geometry" do
    expect([row.dig("summary", "hard_failure"), metrics])
      .to eq([false, [0.0, 0.0, 0.0, 0.0]])
  end
end
