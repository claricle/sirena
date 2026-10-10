# frozen_string_literal: true

require "spec_helper"
require "sirena/layout/quadrant"
require "sirena/diagram/quadrant"

RSpec.describe Sirena::Layout::Quadrant do
  subject(:graph) { described_class.new.to_graph(diagram) }

  let(:diagram) { Sirena::Diagram::Quadrant.new(id: "portfolio") }
  let(:expected_bounds) do
    [[1, 250.0, 5.0, 245.0, 245.0],
     [2, 5.0, 5.0, 245.0, 245.0],
     [3, 5.0, 250.0, 245.0, 245.0],
     [4, 250.0, 250.0, 245.0, 245.0]]
  end

  it "publishes mmdc's 500x500 canvas" do
    expect([graph.class, graph.id, graph.width, graph.height, graph.view_box])
      .to eq([described_class::Scene, "portfolio", 500.0, 500.0,
              "0 0 500 500"])
  end

  it "draws no axis label that was not written" do
    expect(graph.axis_labels).to eq([])
  end

  it "draws mmdc's six border lines around the plot" do
    expect(graph.axes.map { |l| [l.x1, l.y1, l.x2, l.y2, l.stroke_width] })
      .to eq([[4.0, 5.0, 496.0, 5.0, 2.0], [495.0, 6.0, 495.0, 494.0, 2.0],
              [4.0, 495.0, 496.0, 495.0, 2.0], [5.0, 6.0, 5.0, 494.0, 2.0],
              [250.0, 6.0, 250.0, 494.0, 1.0],
              [6.0, 250.0, 494.0, 250.0, 1.0]])
  end

  it "calculates all four quadrant bounds through the public graph" do
    bounds = graph.quadrants.map do |quadrant|
      [quadrant.number, quadrant.x, quadrant.y,
       quadrant.width, quadrant.height]
    end

    expect(bounds).to eq(expected_bounds)
  end

  it "lays out direct shared IR identically to the private diagram" do
    ir = Sirena::Notation::Mermaid::IRAdapters::Quadrant.call(diagram)
    scenes = [diagram, ir].map { |input| described_class.new.call(input) }

    expect(scenes.map { |scene| Marshal.dump(scene) }.uniq.one?).to be(true)
  end

  context "with points" do
    subject(:themed_point_geometry) do
      contrast = described_class.new.call(
        diagram, theme: Sirena::Theme::Registry.get(:high_contrast)
      )
      point = contrast.points.first
      [point.label.x, point.label.y, point.label.font_size,
       contrast.axis_labels.first.font_size]
    end

    let(:diagram) do
      Sirena::Diagram::Quadrant.new(
        points: [default_point, styled_point],
        x_axis_left: "low",
        y_axis_top: "high",
      )
    end
    let(:default_point) do
      Sirena::Diagram::QuadrantPoint.new(label: "default", x: 0.25, y: 0.75)
    end
    let(:styled_point) do
      Sirena::Diagram::QuadrantPoint.new(
        label: "styled", x: 1.0, y: 0.0, radius: 9,
        stroke_color: "navy", stroke_width: 4
      )
    end

    it "normalizes x and inverts y into SVG coordinates" do
      positions = point_values(graph.points, :x, :y)

      expect(positions).to eq([[147.0, 121.0], [495.0, 469.0]])
    end

    it "applies default and custom point geometry" do
      geometry = point_values(
        graph.points, :radius, :stroke_width, :stroke_color
      )

      expect(geometry).to eq([[5, 2, nil], [9.0, 4.0, "navy"]])
    end

    it "draws only the supplied axis labels, x below the plot" do
      expect(graph.axis_labels.map { |l| [l.text, l.x, l.y, l.rotation] })
        .to eq([["low", 31.0, 479.0, 0.0], ["high", 5.0, 121.0, -90.0]])
    end

    it "centres each point label under its circle at mmdc's 12px size" do
      expect(themed_point_geometry).to eq([147.0, 126.0, 12.0, 16.0])
    end
  end

  def point_values(points, *keys)
    points.map { |point| keys.map { |key| point.public_send(key) } }
  end
end
