# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Error do
  let(:case_ids) do
    %w[
      error/002_rendering_errordiagram_spec_error_1.mmd
      error/003_spec_diagram-orchestration_spec_2.mmd
      error/004_spec_diagram-orchestration_spec_3.mmd
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
    root = SpecSupport::LayoutParity::CohortRunner::ROOT
    path = File.join(root, "scoreboard/layout-parity.json")
    rows = JSON.parse(File.read(path))
    rows.select { |row| case_ids.include?(row.fetch("case")) }
  end

  def parity_evidence
    fresh = fresh_rows
    cases = fresh.map { |row| row.fetch("case") }
    [
      cases, invariant_evidence(fresh), metric_evidence(fresh),
      regressions(fresh)
    ]
  end

  def invariant_evidence(rows)
    rows.map do |row|
      row.fetch("invariants").map { |failure| failure["subject_keys"] }
    end.uniq
  end

  def metric_evidence(rows)
    rows.map do |row|
      row.dig("summary", "metrics").values_at(
        "worst_e_c", "worst_e_w", "worst_e_h", "worst_e_a"
      )
    end.uniq
  end

  def regressions(fresh)
    SpecSupport::LayoutParity::ScoreboardRatchet.diff(
      committed: committed_rows, fresh: fresh,
    )[:regressions]
  end

  it "aligns shared error roles without regressing recorded geometry" do
    expect(parity_evidence).to eq(
      [case_ids, [[["error_text", nil, "version"]]],
       [[0.0, 0.0, 0.0, 0.0]], []],
    )
  end
end
