# frozen_string_literal: true

require "spec_helper"
require "sirena/layout/quadrant"
require "sirena/diagram/quadrant"

RSpec.describe Sirena::Layout::Quadrant do
  subject(:graph) { described_class.new.to_graph(diagram) }

  let(:diagram) { Sirena::Diagram::Quadrant.new(id: "portfolio") }
  let(:expected_bounds) do
    [[1, 400.0, 80.0, 320.0, 220.0],
     [2, 80.0, 80.0, 320.0, 220.0],
     [3, 80.0, 300.0, 320.0, 220.0],
     [4, 400.0, 300.0, 320.0, 220.0]]
  end

  it "publishes the fixed canvas and chart dimensions" do
    expect([graph.class, graph.id, graph.width, graph.height, graph.view_box])
      .to eq([described_class::Scene, "portfolio", 800.0, 600.0,
              "0 0 800 600"])
  end

  it "uses empty strings for omitted axis labels" do
    expect(graph.axis_labels.map(&:text)).to eq(["", "", "", ""])
  end

  it "calculates all four quadrant bounds through the public graph" do
    bounds = graph.quadrants.map do |quadrant|
      [quadrant.number, quadrant.x, quadrant.y,
       quadrant.width, quadrant.height]
    end

    expect(bounds).to eq(expected_bounds)
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

      expect(positions).to eq([[240.0, 190.0], [720.0, 520.0]])
    end

    it "applies default and custom point geometry" do
      geometry = point_values(
        graph.points, :radius, :stroke_width, :stroke_color
      )

      expect(geometry).to eq([[6, 2, nil], [9.0, 4.0, "navy"]])
    end

    it "preserves supplied axes while defaulting omitted labels" do
      expect(graph.axis_labels.map(&:text)).to eq(["low", "", "", "high"])
    end

    it "stores final point-label geometry and themed font sizes" do
      expect(themed_point_geometry).to eq([250.0, 180.0, 14.0, 14.0])
    end
  end

  def point_values(points, *keys)
    points.map { |point| keys.map { |key| point.public_send(key) } }
  end
end
