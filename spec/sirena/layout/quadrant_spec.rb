# frozen_string_literal: true

require "spec_helper"
require "sirena/layout/quadrant"
require "sirena/diagram/quadrant"

RSpec.describe Sirena::Layout::Quadrant do
  subject(:graph) { described_class.new.to_graph(diagram) }

  let(:diagram) { Sirena::Diagram::Quadrant.new(id: "portfolio") }

  it "publishes the fixed canvas and chart dimensions" do
    expect(graph).to include(
      id: "portfolio",
      dimensions: {
        width: 800, height: 600, margin: 80, chart_width: 640,
        chart_height: 440, chart_x: 80, chart_y: 80
      },
    )
  end

  it "uses empty strings for omitted axis labels" do
    expect(graph[:axes]).to eq(x_left: "", x_right: "", y_bottom: "", y_top: "")
  end

  it "calculates all four quadrant bounds through the public graph" do
    bounds = graph[:quadrants].transform_values { |quadrant| quadrant[:bounds] }

    expect(bounds).to eq(
      q1: { x: 400.0, y: 80, width: 320.0, height: 220.0 },
      q2: { x: 80, y: 80, width: 320.0, height: 220.0 },
      q3: { x: 80, y: 300.0, width: 320.0, height: 220.0 },
      q4: { x: 400.0, y: 300.0, width: 320.0, height: 220.0 },
    )
  end

  context "with points" do
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
      expect(graph[:points].map { |point| point.values_at(:svg_x, :svg_y) }).to eq(
        [[240.0, 190.0], [720.0, 520.0]],
      )
    end

    it "applies default and custom point geometry" do
      expect(graph[:points].map { |point| point.values_at(:radius, :stroke_width, :stroke_color) }).to eq(
        [[6, 2, nil], [9.0, 4.0, "navy"]],
      )
    end

    it "preserves supplied axes while defaulting omitted labels" do
      expect(graph[:axes]).to eq(x_left: "low", x_right: "", y_bottom: "", y_top: "high")
    end
  end
end
