# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::LayoutParity::ScoreboardRatchet do
  let(:row) do
    lambda do |case_id:, hard_failure: false, metrics: {}, reference: "ref.svg"|
      defaults = described_class::METRICS.to_h { |metric| [metric, nil] }
      {
        "case" => case_id,
        "reference" => reference,
        "summary" => {
          "hard_failure" => hard_failure,
          "metrics" => defaults.merge(metrics),
        },
      }
    end
  end
  let(:compare) do
    lambda do |committed, fresh|
      described_class.diff(committed: committed, fresh: fresh)
    end
  end
  let(:metric_row) do
    lambda do |metric, value, hard_failure: false|
      row.call(case_id: "a", hard_failure: hard_failure,
               metrics: { metric => value })
    end
  end
  let(:all_metric_row) do
    lambda do |value|
      metrics = described_class::METRICS.to_h { |metric| [metric, value] }
      row.call(case_id: "a", metrics: metrics)
    end
  end
  let(:change_values) do
    lambda do |changes|
      changes.map { |change| change.values_at(:field, :before, :after) }
    end
  end

  it "reports no drift for identical rows in different input order" do
    first = row.call(case_id: "a", metrics: { "worst_e_c" => 0.1 })
    second = row.call(case_id: "b", hard_failure: true)

    expect(compare.call([first, second], [second, first]))
      .to eq(missing: [], new: [], stale: [], regressions: [],
             unrecorded_improvements: [])
  end

  it "reports every missing and new row, including hard failures" do
    committed = [row.call(case_id: "gone", hard_failure: true)]
    fresh = [row.call(case_id: "added", hard_failure: true)]
    diff = described_class.diff(committed: committed, fresh: fresh)

    expect(diff.values_at(:missing, :new)).to eq([%w[gone], %w[added]])
  end

  it "reports every worsened metric as a regression" do
    diff = compare.call([all_metric_row.call(0.1)],
                        [all_metric_row.call(0.2)])
    fields = diff[:regressions].map { |change| change.fetch(:field) }

    expect(fields).to eq(described_class::METRICS)
  end

  it "orders infinity above finite metric values" do
    finite = metric_row.call("worst_e_w", 0.2)
    infinite = metric_row.call("worst_e_w", "Infinity")
    worse = compare.call([finite], [infinite])[:regressions]
    better = compare.call([infinite], [finite])[:unrecorded_improvements]

    expect(worse + better).to all(include(field: "worst_e_w"))
  end

  it "reports a newly introduced hard failure as a regression" do
    good = row.call(case_id: "a")
    bad = row.call(case_id: "a", hard_failure: true)
    diff = compare.call([good], [bad])
    actual = diff[:regressions].first.values_at(:case, :field, :before, :after)

    expect(actual).to eq(["a", "hard_failure", false, true])
  end

  it "reports resolved hard failures and smaller metrics as improvements" do
    before = metric_row.call("worst_e_c", 0.4, hard_failure: true)
    after = metric_row.call("worst_e_c", 0.1)
    changes = compare.call([before], [after])[:unrecorded_improvements]
    expected = [["hard_failure", true, false], ["worst_e_c", 0.4, 0.1]]

    expect(change_values.call(changes)).to eq(expected)
  end

  it "marks non-metric evidence changes stale without inventing an order" do
    committed = row.call(case_id: "a")
    fresh = row.call(case_id: "a", reference: "new-ref.svg")
    diff = described_class.diff(committed: [committed], fresh: [fresh])

    expect(diff).to include(stale: ["a"], regressions: [],
                            unrecorded_improvements: [])
  end

  it "marks nil-to-number metrics stale without calling them improvements" do
    committed = row.call(case_id: "a")
    fresh = row.call(case_id: "a", metrics: { "worst_e_h" => 0.1 })
    diff = described_class.diff(committed: [committed], fresh: [fresh])

    expect(diff).to include(stale: ["a"], regressions: [],
                            unrecorded_improvements: [])
  end

  it "rejects duplicate IDs in either ledger" do
    duplicate = row.call(case_id: "a")

    expect do
      described_class.diff(committed: [duplicate, duplicate], fresh: [])
    end.to raise_error(ArgumentError, /duplicate case ID.*a/)
  end
end
