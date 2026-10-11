# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Mindmap do
  let(:case_ids) do
    %w[
      mindmap/mindmap_spec-457a34d3.mmd
      mindmap/mmp_10_multiple_types_circle-99fb2764.mmd
      mindmap/mmp_11_multiple_types_cloud-c07ee2e8.mmd
      mindmap/mmp_12_multiple_types_bang-5a0a76dc.mmd
    ]
  end
  let(:expected_metrics) do
    {
      case_ids[0] => [0.003432, 0.006776, 0.006403, 0.001115],
      case_ids[1] => [0.000147, 0.000293, 0.000293, 0.0],
      case_ids[2] => [0.000151, 0.000202, 0.00043, 0.000228],
      case_ids[3] => [0.000409, 0.00095, 0.0, 0.00095],
    }
  end
  let(:parity_evidence) do
    runner = SpecSupport::LayoutParity::CohortRunner.new
    results = runner.comparison_cases.filter_map do |candidate|
      runner.send(:compare, candidate) if case_ids.include?(candidate.case_id)
    end
    SpecSupport::LayoutParity::CaseLedger.build(results).to_h do |row|
      metrics = row.dig("summary", "metrics")
      [row.fetch("case"),
       [row.dig("summary", "hard_failure"), row.dig("geometry", "matched"),
        metrics.values_at("worst_e_c", "worst_e_w", "worst_e_h",
                          "worst_e_a")]]
    end
  end

  it "matches the browser-sized circle, cloud, and bang geometry" do
    expected = expected_metrics.transform_values do |metrics|
      [false, 1, metrics]
    end
    expected[case_ids[0]][1] = 3

    expect(parity_evidence).to eq(expected)
  end

  it "measures ordinary Mindmap labels in Mermaid's Trebuchet face" do
    scene = described_class.new.call(
      Sirena::Parser::Mindmap.new.parse("mindmap\n  root((the root))\n"),
    )

    expect(scene.children.first)
      .to have_attributes(width: 78.352, height: 78.352)
  end
end
