# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::LayoutParity::MeasurementPolicy do
  let(:expected_spatial_kinds) do
    {
      architecture: %i[architecture_group architecture_service],
      block: %i[block_container block_leaf],
      c4: %i[c4_boundary c4_element],
      class_diagram: %i[class],
      er_diagram: %i[entity],
      flowchart: %i[node cluster],
      gantt: %i[task],
      kanban: %i[section card],
      mindmap: %i[mindmap_node],
      packet: %i[field],
      requirement: %i[requirement element],
      sequence: %i[participant-top participant-bottom],
      state_diagram: %i[composite state terminal-start terminal-end],
      treemap: %i[treemap_section treemap_leaf],
      user_journey: %i[journey_section journey_task],
    }
  end

  describe ".for" do
    it "selects every node-like kind named by the metric contract" do
      expect(actual_spatial_kinds).to eq(expected_spatial_kinds)
    end

    it "makes non-node overlap exemptions explicit" do
      exempt = %i[error git_graph info pie quadrant radar sankey timeline
                  xychart]

      expect(exempt).to all(satisfy do |type|
        described_class.for(type).spatial_kinds.empty?
      end)
    end

    it "wires every settled scalar analog to live SVGs" do
      expect(analog_summaries).to match(analog_matchers)
    end

    it "has no scalar analog for types without one in the contract" do
      policy = described_class.for(:flowchart)

      expect(policy.analog_measurements).to be_nil
    end

    it "records an unpairable analog instead of dropping the case" do
      expect(unpairable_analog).to eq(unpairable_evidence)
    end

    it "does not turn an unexpected analog defect into baseline evidence" do
      allow(SpecSupport::LayoutParity::RadarGraticuleGeometry)
        .to receive(:compare).and_raise(ArgumentError, "unexpected defect")
      expect { unpairable_analog }
        .to raise_error(ArgumentError, "unexpected defect")
    end
  end

  def actual_spatial_kinds
    expected_spatial_kinds.to_h do |type, _kinds|
      [type, described_class.for(type).spatial_kinds]
    end
  end

  def analog_summaries
    {
      pie: analog_summary(:pie, "002_rendering_pie_spec_pie_1"),
      quadrant: analog_summary(:quadrant, "001_example_quadrant-chart_0"),
      radar: analog_summary(:radar, "001_rendering_radar_spec_radar_0"),
      git_graph: analog_summary(:git_graph, "002_platform_showcase_base_1"),
    }
  end

  def analog_matchers
    {
      pie: [be > 0, include(:radius, :sweep_angle)],
      quadrant: [6, [:radius]],
      radar: [5, [:radius]],
      git_graph: [18, [:radius]],
    }
  end

  def unpairable_analog
    policy = described_class.for(:radar)
    policy.analog_measurements.call(reference_svg: one_graticule,
                                    sirena_svg: two_graticules)
  end

  def unpairable_evidence
    [{ key: [:radar, :measurement_error, "graticule counts differ"],
       error: Float::INFINITY }]
  end

  def one_graticule
    '<svg><circle class="radarGraticule" r="5"/></svg>'
  end

  def two_graticules
    '<svg><circle fill="none" r="5"/>' \
      '<circle fill="none" r="9"/></svg>'
  end

  def analog_summary(type, basename)
    policy = described_class.for(type)
    reference = File.read(reference_path(type, basename))
    source = File.read(corpus_path(type, basename))
    rows = policy.analog_measurements.call(
      reference_svg: reference,
      sirena_svg: Sirena.render(source),
    )
    [rows.size, rows.map { |row| row.fetch(:key).last }.uniq]
  end

  def reference_path(type, basename)
    directory = type == :git_graph ? "gitgraph" : type.to_s
    "spec/fixtures_mermaid/#{directory}/#{basename}.svg"
  end

  def corpus_path(type, basename)
    directory = type == :git_graph ? "gitgraph" : type.to_s
    "spec/mermaid/#{directory}/#{basename}.mmd"
  end
end
