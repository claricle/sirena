# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::LayoutParity::CaseComparator do
  include SpecSupport::LayoutParity::FigureHelpers

  subject(:comparison) { described_class.compare(**arguments) }

  let(:arguments) do
    {
      case_id: "flowchart/example",
      type: "flowchart",
      reference: "spec/fixtures_mermaid/flowchart/example.svg",
      reference_svg: <<~REFERENCE,
        <svg viewBox="0 0 100 100">
          <g class="node" id="flowchart-a-0"><rect x="0" y="0" width="10" height="10"/></g>
          <g class="node" id="flowchart-b-1"><rect x="30" y="0" width="10" height="10"/></g>
        </svg>
      REFERENCE
      sirena_svg: <<~SIRENA,
        <svg viewBox="0 0 100 100">
          <g id="node-a"><rect x="0" y="0" width="10" height="10"/></g>
          <g id="node-b"><rect x="30" y="0" width="20" height="10"/></g>
        </svg>
      SIRENA
      reproduce: "bundle exec rspec spec/layout_parity_spec.rb",
      recognizer: SpecSupport::LayoutParity::FlowchartRecognizer.new,
    }
  end

  context "with normalized analog measurements" do
    let(:analogs) do
      lambda do |reference_svg:, sirena_svg:|
        raise "missing reference" if reference_svg.empty?
        raise "missing candidate" if sirena_svg.empty?

        [{ key: [:point, "b"], error: 0.4 },
         { key: [:point, "a"], error: 0.1 }]
      end
    end
    let(:arguments) { super().merge(analog_measurements: analogs) }
    let(:summary) do
      evidence = comparison.to_h
      geometry = evidence.fetch(:geometry)
      [evidence[:sirena_status], evidence[:invariants],
       geometry.values_at(:worst_e_w, :worst_analog, :matched, :ambiguous),
       geometry.dig(:worst_keys, :analog), geometry[:top5].size]
    end
    let(:expected) do
      ["rendered", [], [1.0, 0.4, 2, 0], [:point, "b"], 2]
    end

    it "assembles matcher, geometry, and worst-analog evidence" do
      expect(summary).to eq(expected)
    end
  end

  context "with a missing candidate element" do
    subject(:failure) { comparison.to_h[:invariants].first }

    let(:arguments) do
      candidate = super().fetch(:sirena_svg)
        .sub(/\s*<g id="node-b".*<\/g>/, "")
      super().merge(sirena_svg: candidate)
    end
    let(:expected) do
      {
        rule: "element-presence",
        subject_keys: [:node, nil, "b"],
        expected: 1,
        actual: 0,
        normalized: include(match_by: :id, difference: :missing),
      }
    end

    it "turns matcher count differences into presence evidence" do
      expect(failure).to include(expected)
    end
  end

  context "with duplicate identities on both sides" do
    let(:arguments) do
      reference = super().fetch(:reference_svg).sub(
        "</svg>",
        '<g class="node" id="flowchart-a-2">' \
        '<rect width="5" height="5"/></g></svg>',
      )
      sirena = super().fetch(:sirena_svg).sub(
        "</svg>", '<g id="node-a"><rect width="5" height="5"/></g></svg>'
      )
      super().merge(reference_svg: reference, sirena_svg: sirena)
    end

    it "carries the matched and ambiguous counts into geometry evidence" do
      expect(comparison.to_h[:geometry].values_at(:matched, :ambiguous))
        .to eq([3, 2])
    end
  end

  context "with caller-selected node-like elements" do
    let(:arguments) do
      overlapping = super().fetch(:sirena_svg).sub('x="30"', 'x="5"')
      super().merge(sirena_svg: overlapping, spatial_kinds: [:node])
    end

    it "runs the spatial checker" do
      expect(comparison.to_h[:invariants])
        .to include(include(rule: "peer-overlap"))
    end
  end

  context "without a reference" do
    let(:arguments) { super().merge(reference_svg: nil) }
    let(:summary) do
      evidence = comparison.to_h
      failure = evidence[:invariants].first
      failure.values_at(:rule, :subject_keys, :expected, :actual) +
        evidence[:geometry].values_at(:matched, :worst_e_c)
    end

    it "records a hard invariant failure and empty geometry" do
      expect(summary).to eq(["reference-presence", ["flowchart/example"],
                             arguments[:reference], nil, 0, nil])
    end
  end

  context "when candidate rendering failed" do
    let(:error) { { error_stage: "layout", message: "elkrb raised" } }
    let(:arguments) { super().merge(sirena_svg: nil, render_error: error) }

    it "records render-stage evidence without parsing a candidate" do
      evidence = comparison.to_h
      summary = [evidence[:sirena_status],
                 evidence[:geometry].values_at(:matched, :worst_analog)]
      expect(summary).to eq([error, [0, nil]])
    end
  end

  context "with one real Flowchart pair" do
    let(:arguments) do
      reference, sirena = flowchart_sides("001_config_0")
      super().merge(reference_svg: reference, sirena_svg: sirena)
    end

    it "assembles the real matched geometry evidence" do
      evidence = comparison.to_h
      summary = [evidence[:sirena_status], evidence[:geometry][:matched],
                 evidence[:geometry][:top5].empty?]
      expect(summary).to eq(["rendered", 6, false])
    end
  end
end
