# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/quadrant"

RSpec.describe Sirena::Parser::QuadrantParser do
  let(:parser) { described_class.new }

  describe "#parse" do
    it "parses a simple quadrant chart" do
      source = <<~QUADRANT
        quadrantChart
          title Product Analysis
          x-axis Low Cost --> High Cost
          y-axis Low Value --> High Value
          quadrant-1 Invest
          quadrant-2 Evaluate
          quadrant-3 Divest
          quadrant-4 Maintain
          Product A: [0.3, 0.7]
      QUADRANT

      diagram = parser.parse(source)

      expect(diagram).to be_a(Sirena::Diagram::QuadrantChart)
      expect(diagram.title).to eq("Product Analysis")
      expect(diagram.x_axis_left).to eq("Low Cost")
      expect(diagram.x_axis_right).to eq("High Cost")
      expect(diagram.y_axis_bottom).to eq("Low Value")
      expect(diagram.y_axis_top).to eq("High Value")
      expect(diagram.quadrant_1_label).to eq("Invest")
      expect(diagram.quadrant_2_label).to eq("Evaluate")
      expect(diagram.quadrant_3_label).to eq("Divest")
      expect(diagram.quadrant_4_label).to eq("Maintain")
      expect(diagram.points.length).to eq(1)
      expect(diagram.points.first.label).to eq("Product A")
      expect(diagram.points.first.x).to eq(0.3)
      expect(diagram.points.first.y).to eq(0.7)
    end

    it "parses quadrant chart with multiple points" do
      source = <<~QUADRANT
        quadrantChart
          x-axis Left --> Right
          y-axis Bottom --> Top
          Point A: [0.2, 0.8]
          Point B: [0.7, 0.3]
          Point C: [0.5, 0.5]
      QUADRANT

      diagram = parser.parse(source)

      expect(diagram.points.length).to eq(3)
      expect(diagram.points[0].label).to eq("Point A")
      expect(diagram.points[1].label).to eq("Point B")
      expect(diagram.points[2].label).to eq("Point C")
    end

    it "parses points with styling parameters" do
      source = <<~QUADRANT
        quadrantChart
          x-axis Left --> Right
          y-axis Bottom --> Top
          Product A: [0.5, 0.5] radius: 10
          Product B: [0.3, 0.7] radius: 8, color: #ff0000
          Product C: [0.8, 0.2] radius: 12, color: #00ff00, stroke-color: #0000ff
          Product D: [0.1, 0.9] radius: 10, color: #ff0000, stroke-color: #00ff00, stroke-width: 3px
      QUADRANT

      diagram = parser.parse(source)

      expect(diagram.points.length).to eq(4)

      # Product A - radius only
      expect(diagram.points[0].radius).to eq(10.0)

      # Product B - radius and color
      expect(diagram.points[1].radius).to eq(8.0)
      expect(diagram.points[1].color).to eq("#ff0000")

      # Product C - radius, color, stroke-color
      expect(diagram.points[2].radius).to eq(12.0)
      expect(diagram.points[2].color).to eq("#00ff00")
      expect(diagram.points[2].stroke_color).to eq("#0000ff")

      # Product D - all parameters
      expect(diagram.points[3].radius).to eq(10.0)
      expect(diagram.points[3].color).to eq("#ff0000")
      expect(diagram.points[3].stroke_color).to eq("#00ff00")
      expect(diagram.points[3].stroke_width).to eq(3.0)
    end

    it "parses quoted axis labels" do
      source = <<~QUADRANT
        quadrantChart
          x-axis "Low Cost ❤" --> "High Cost"
          y-axis "Low Value" --> "High Value"
          Product: [0.5, 0.5]
      QUADRANT

      diagram = parser.parse(source)

      expect(diagram.x_axis_left).to eq("Low Cost ❤")
      expect(diagram.x_axis_right).to eq("High Cost")
    end

    it "parses minimal quadrant chart with just header" do
      source = <<~QUADRANT
        quadrantChart
          x-axis Left --> Right
          y-axis Bottom --> Top
      QUADRANT

      diagram = parser.parse(source)

      expect(diagram).to be_a(Sirena::Diagram::QuadrantChart)
      expect(diagram.points).to be_empty
    end

    it "validates diagram structure" do
      source = <<~QUADRANT
        quadrantChart
          title Campaign Analysis
          x-axis Low Reach --> High Reach
          y-axis Low Engagement --> High Engagement
          Campaign A: [0.3, 0.6]
      QUADRANT

      diagram = parser.parse(source)

      expect(diagram.valid?).to be true
    end

    it "determines point quadrants correctly" do
      source = <<~QUADRANT
        quadrantChart
          x-axis Left --> Right
          y-axis Bottom --> Top
          Q1 Point: [0.7, 0.7]
          Q2 Point: [0.3, 0.7]
          Q3 Point: [0.3, 0.3]
          Q4 Point: [0.7, 0.3]
      QUADRANT

      diagram = parser.parse(source)

      expect(diagram.points[0].quadrant).to eq(1)
      expect(diagram.points[1].quadrant).to eq(2)
      expect(diagram.points[2].quadrant).to eq(3)
      expect(diagram.points[3].quadrant).to eq(4)
    end
  end

  describe "fixture files" do
    Dir.glob("spec/mermaid/quadrant/*.mmd").each do |fixture_file|
      it "parses #{File.basename(fixture_file)}" do
        source = File.read(fixture_file)

        expect { parser.parse(source) }.not_to raise_error
      end
    end
  end
end