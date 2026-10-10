# frozen_string_literal: true

require "json"
require "spec_helper"

RSpec.describe SpecSupport::LayoutParity::CaseLedger do
  let(:case_result) { SpecSupport::LayoutParity::CaseResult }
  let(:geometry) do
    {
      worst_e_c: 0.1,
      worst_e_w: 0.2,
      worst_e_h: nil,
      worst_e_a: Float::INFINITY,
      worst_analog: 0.3,
      worst_keys: { e_c: [:node, nil, "a"] },
      matched: 1,
      ambiguous: 0,
      top5: [],
    }
  end
  let(:build_result) do
    lambda do |case_id:, invariants: [], measured_geometry: geometry|
      case_result.new(
        case_id: case_id,
        type: "flowchart",
        reference: "spec/fixtures_mermaid/#{case_id}.svg",
        sirena_status: "rendered",
        invariants: invariants,
        geometry: measured_geometry,
        reproduce: "bundle exec rspec spec/layout_parity_spec.rb",
      )
    end
  end
  let(:ledger_results) do
    failure = { rule: "element-presence", subject_keys: [:node, "b"] }
    [build_result.call(case_id: "flowchart/b", invariants: [failure]),
     build_result.call(case_id: "flowchart/a")]
  end
  let(:expected_summary) do
    {
      "hard_failure" => true,
      "metrics" => {
        "worst_e_c" => 0.1,
        "worst_e_w" => 0.2,
        "worst_e_h" => nil,
        "worst_e_a" => "Infinity",
        "worst_analog" => 0.3,
      },
    }
  end

  it "builds sorted JSON evidence with failure and metric summaries" do
    rows = described_class.build(ledger_results)
    ids = rows.map { |row| row.fetch("case") }
    failures = rows.map { |row| row.dig("summary", "hard_failure") }
    expected = [%w[flowchart/a flowchart/b], [false, true], expected_summary]

    expect([ids, failures, rows.last["summary"]]).to eq(expected)
  end

  it "deep-normalizes evidence into JSON values without losing infinity" do
    rows = described_class.build([build_result.call(case_id: "flowchart/a")])
    parsed = JSON.parse(JSON.generate(rows))
    summary = [parsed.dig(0, "geometry", "worst_e_a"),
               parsed.dig(0, "geometry", "worst_keys", "e_c")]

    expect(summary).to eq(["Infinity", ["node", nil, "a"]])
  end

  it "collapses float noise below the scoreboard precision" do
    expected = [0.123456789012, 0.123456789012]
    expect(recorded_noisy_centers).to eq([expected, expected])
  end

  it "keeps meaningful center-threshold changes detectable" do
    expect(center_regressions(0.08, 0.080001))
      .to include(include(field: "worst_e_c", before: 0.08, after: 0.080001))
  end

  it "rejects duplicate case IDs instead of overwriting a row" do
    duplicate = build_result.call(case_id: "flowchart/a")

    expect { described_class.build([duplicate, duplicate]) }
      .to raise_error(ArgumentError, /duplicate case ID.*flowchart\/a/)
  end

  it "rejects an empty case ID" do
    result = build_result.call(case_id: "")

    expect { described_class.build([result]) }
      .to raise_error(ArgumentError, /non-empty string/)
  end

  it "rejects non-JSON evidence rather than stringifying it implicitly" do
    result = build_result.call(case_id: "flowchart/a")
      .with(invariants: [{ rule: Object.new }])

    expect { described_class.build([result]) }
      .to raise_error(ArgumentError, /JSON value/)
  end

  def ledger_with_center(value, case_id: "flowchart/a")
    measured_geometry = geometry.merge(worst_e_c: value)
    result = build_result.call(case_id: case_id,
                               measured_geometry: measured_geometry)
    described_class.build([result])
  end

  def recorded_noisy_centers
    [0.12345678901231, 0.12345678901239].map.with_index do |value, index|
      row = ledger_with_center(value, case_id: "flowchart/#{index}").fetch(0)
      [row.dig("geometry", "worst_e_c"),
       row.dig("summary", "metrics", "worst_e_c")]
    end
  end

  def center_regressions(before, after)
    SpecSupport::LayoutParity::ScoreboardRatchet.diff(
      committed: ledger_with_center(before),
      fresh: ledger_with_center(after),
    ).fetch(:regressions)
  end
end
