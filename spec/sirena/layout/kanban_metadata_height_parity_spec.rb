# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Kanban do
  let(:case_ids) do
    %w[
      kanban/kanban_spec-af29b4d6.mmd
      kanban/kanban_spec-cf23b2fc.mmd
      kanban/kanban_spec-e33c6002.mmd
    ]
  end
  let(:runner) { SpecSupport::LayoutParity::CohortRunner.new }
  let(:fresh_rows) do
    results = runner.comparison_cases.filter_map do |candidate|
      runner.send(:compare, candidate) if candidate.case_id.start_with?("kanban/")
    end
    SpecSupport::LayoutParity::CaseLedger.build(results)
  end
  let(:committed_rows) do
    path = File.join(SpecSupport::LayoutParity::CohortRunner::ROOT,
                     "scoreboard/layout-parity.json")
    JSON.parse(File.read(path)).select do |row|
      row.fetch("case").start_with?("kanban/")
    end
  end
  let(:diff) do
    SpecSupport::LayoutParity::ScoreboardRatchet.diff(
      committed: committed_rows, fresh: fresh_rows,
    )
  end

  it "matches metadata card geometry without changing other Kanban cases" do
    exact_metrics = fresh_rows.filter_map do |row|
      next unless case_ids.include?(row.fetch("case"))

      row.dig("summary", "metrics").values_at(
        "worst_e_c", "worst_e_w", "worst_e_h", "worst_e_a",
      )
    end

    expect(fresh_rows.length).to eq(39)
    expect(exact_metrics).to contain_exactly([0.0, 0.0, 0.0, 0.0],
                                             [0.0, 0.0, 0.0, 0.0],
                                             [0.0, 0.0, 0.0, 0.0])
    expect(diff).to include(
      missing: [], new: [], regressions: [], stale: case_ids,
    )
    expect(diff.fetch(:unrecorded_improvements).length).to eq(9)
  end
end
