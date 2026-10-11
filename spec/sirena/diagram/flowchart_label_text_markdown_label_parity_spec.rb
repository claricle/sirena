# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Diagram::FlowchartLabelText do
  let(:case_ids) do
    %w[
      unknown/knsv-1307e7ca.mmd
      unknown/knsv-2f8c3deb.mmd
      unknown/knsv-5441fe6f.mmd
    ]
  end
  let(:parity_rows) do
    runner = SpecSupport::LayoutParity::CohortRunner.new
    results = runner.comparison_cases.filter_map do |candidate|
      runner.send(:compare, candidate) if case_ids.include?(candidate.case_id)
    end
    SpecSupport::LayoutParity::CaseLedger.build(results)
  end
  let(:expected_metrics) do
    {
      "unknown/knsv-1307e7ca.mmd" =>
        [0.058165, 0.094904, 0.0, 0.094904],
      "unknown/knsv-2f8c3deb.mmd" =>
        [0.041929, 0.083779, 0.0, 0.083779],
      "unknown/knsv-5441fe6f.mmd" =>
        [0.053519, 0.085082, 0.0, 0.085082],
    }
  end

  let(:evidence) do
    parity_rows.to_h do |row|
      summary = row.fetch("summary")
      metrics = summary.fetch("metrics").values_at(
        "worst_e_c", "worst_e_w", "worst_e_h", "worst_e_a"
      )
      [row.fetch("case"), [summary.fetch("hard_failure"), metrics]]
    end
  end

  it "turns a quoted escaped newline into a hard label break" do
    expect(described_class.lines('"first\\nsecond"'))
      .to eq(%w[first second])
  end

  it "leaves an unquoted escaped newline in the label" do
    expect(described_class.lines("first\\nsecond"))
      .to eq(["first\\nsecond"])
  end

  it "draws Mermaid markdown strings without their source markers" do
    written = '"`The dog in **the** hog.(1)\nNL`"'

    expect(described_class.lines(written))
      .to eq(["The dog in the hog.(1)", "NL"])
  end

  it "displays a markdown label without its emphasis markers" do
    expect(described_class.display("`1o **bold**`")).to eq("1o bold")
  end

  it "brings all three reference cases within the geometry thresholds" do
    expect(evidence).to eq(expected_metrics.transform_values do |metrics|
      [false, metrics]
    end)
  end
end
