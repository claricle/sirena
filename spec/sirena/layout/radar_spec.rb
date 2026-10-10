# frozen_string_literal: true

require "spec_helper"
require "sirena/layout/radar"
require "sirena/diagram/radar"
require "sirena/notation/mermaid/ir_adapters/radar"

RSpec.describe Sirena::Layout::Radar do
  subject(:graph) { described_class.new.to_graph(diagram) }

  let(:diagram) { Sirena::Diagram::Radar.new }

  context "without axes" do
    subject(:empty_scene_geometry) do
      [graph.class, graph.axes, graph.curves, graph.grid_circles.map(&:radius),
       graph.center_x, graph.center_y, graph.radius, graph.width, graph.height,
       graph.min_value, graph.max_value, graph.view_box]
    end

    it "keeps the default canvas with the default rings" do
      expected = [described_class::Scene, [], [], [60.0, 120.0, 180.0, 240.0, 300.0],
                  350.0, 350.0, 300.0, 700.0, 700.0, 0.0, 100.0, "0 0 700 700"]

      expect(empty_scene_geometry).to eq(expected)
    end
  end

  context "with axes and a curve" do
    let(:diagram) do
      Sirena::Diagram::Radar.new.tap do |radar|
        radar.axes = [
          Sirena::Diagram::RadarAxis.new("speed", "Speed"),
          Sirena::Diagram::RadarAxis.new("quality", "Quality"),
        ]
        radar.curves = [curve]
      end
    end
    let(:curve) do
      Sirena::Diagram::RadarCurve.new("current", "Current").tap do |data|
        data.add_value("speed", 10)
        data.add_value("quality", 30)
      end
    end

    it "infers the value range and publishes final dimensions" do
      expect(
        [graph.min_value, graph.max_value, graph.center_x, graph.center_y,
         graph.radius, graph.width, graph.height, graph.view_box],
      ).to eq([0.0, 30.0, 350.0, 350.0, 300.0, 700.0, 700.0,
               "0 0 700 700"])
    end

    context "with positioned axes" do
      subject(:axis_evidence) do
        speed, quality = graph.axes
        actual = [[speed.id, speed.angle, speed.line.x1, speed.line.y1,
                   speed.line.x2.round(4), speed.line.y2,
                   speed.label.x.round(4), speed.label.y,
                   speed.label.text_anchor, speed.label.dominant_baseline],
                  [quality.id, quality.angle, quality.line.x2.round(4),
                   quality.line.y2, quality.label.x.round(4), quality.label.y]]
        expected = [["speed", -90.0, 350.0, 350.0, 350.0, 50.0, 350.0,
                     35.0, "middle", "middle"],
                    ["quality", 90.0, 350.0, 650.0, 350.0, 665.0]]

        [actual, expected]
      end

      it "positions axes clockwise from the top" do
        expect(axis_evidence.first).to eq(axis_evidence.last)
      end
    end

    context "with normalized curve points" do
      subject(:curve_geometry) do
        rendered_curve = graph.curves.first
        points = rendered_curve.points.map do |point|
          [point.axis_id, point.value, point.normalized.round(4),
           point.x.round(4), point.y.round(4)]
        end

        [rendered_curve.id, rendered_curve.label, points]
      end

      it "normalizes points onto their axes" do
        expect(curve_geometry).to eq(
          ["current", "Current",
           [["speed", 10.0, 0.3333, 350.0, 250.0],
            ["quality", 30.0, 1.0, 350.0, 650.0]]],
        )
      end
    end

    it "creates five evenly spaced grid circles across the range" do
      expect(graph.grid_circles.map(&:radius)).to eq(
        [60.0, 120.0, 180.0, 240.0, 300.0],
      )
    end

    it "lays out shared data IR identically to the private model" do
      diagram.options = { min: 0, max: 40, show_legend: false }
      data = Sirena::Notation::Mermaid::IRAdapters::Radar.call(diagram)

      expect(described_class.new.call(data)).to eq(graph)
    end

    context "with a larger theme" do
      subject(:themed_geometry) do
        contrast = described_class.new.call(
          diagram, theme: Sirena::Theme::Registry.get(:high_contrast)
        )
        [contrast.axes.first.label.font_size,
         contrast.legend.first.marker.x, contrast.legend.first.marker.y,
         contrast.legend.first.label.x, contrast.legend.first.label.y,
         contrast.legend.first.label.font_size]
      end

      it "stores label and legend geometry in the scene" do
        expect(themed_geometry).to eq(
          [16.0, 618.5, 93.5, 628.5, 87.5, 14.0],
        )
      end
    end
  end

  context "with configured ranges" do
    let(:diagram) do
      Sirena::Diagram::Radar.new.tap do |radar|
        radar.axes = [Sirena::Diagram::RadarAxis.new("axis")]
        radar.options = { min: -10, max: 10 }
      end
    end

    it "uses the configured minimum and maximum" do
      expect([graph.min_value, graph.max_value]).to eq([-10.0, 10.0])
    end
  end

  it "repairs collapsed and decreasing configured ranges" do
    ranges = [[5, 5], [10, 2]].map { |min, max| graph_for_range(min, max) }

    expect(ranges).to eq([[5, 6], [10, 11]])
  end

  context "with colliding axis and series identifiers" do
    subject(:ir_graph) do
      data = Sirena::Notation::Mermaid::IRAdapters::Radar.call(diagram)

      described_class.new.call(data)
    end

    let(:diagram) do
      Sirena::Diagram::Radar.new.tap do |radar|
        radar.axes = [Sirena::Diagram::RadarAxis.new("same", "Axis")]
        radar.curves = [colliding_curve]
      end
    end
    let(:colliding_curve) do
      Sirena::Diagram::RadarCurve.new("same", "Curve").tap do |curve|
        curve.add_value("same", 5)
      end
    end

    it { is_expected.to eq(graph) }
  end

  def graph_for_range(min, max)
    radar = Sirena::Diagram::Radar.new
    radar.axes = [Sirena::Diagram::RadarAxis.new("axis")]
    radar.options = { min: min, max: max }
    result = described_class.new.to_graph(radar)
    [result.min_value, result.max_value]
  end
end
