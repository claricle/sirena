# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Kanban do
  let(:case_ids) do
    %w[
      kanban/001_rendering_kanban_spec_kanban_0.mmd
      kanban/002_rendering_kanban_spec_kanban_1.mmd
      kanban/003_rendering_kanban_spec_kanban_2.mmd
      kanban/004_rendering_kanban_spec_kanban_3.mmd
    ]
  end

  def fresh_rows
    runner = SpecSupport::LayoutParity::CohortRunner.new
    results = runner.candidate_cases.filter_map do |candidate|
      runner.send(:compare, candidate) if case_ids.include?(candidate.case_id)
    end
    SpecSupport::LayoutParity::CaseLedger.build(results)
  end

  def committed_rows
    path = SpecSupport::LayoutParity::CohortRunner::ROOT
    scoreboard = File.join(path, "scoreboard/layout-parity.json")
    rows = JSON.parse(File.read(scoreboard))
    rows.select { |row| case_ids.include?(row.fetch("case")) }
  end

  def parity_evidence
    fresh = fresh_rows
    diff = SpecSupport::LayoutParity::ScoreboardRatchet.diff(
      committed: committed_rows, fresh: fresh,
    )
    [fresh.none? { |row| row.dig("summary", "hard_failure") },
     diff[:regressions]]
  end

  it "recovers wrapped cards without regressing recorded geometry" do
    expect(parity_evidence).to eq([true, []])
  end
end
