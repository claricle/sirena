# frozen_string_literal: true

require "spec_helper"
require "sirena/renderer/quadrant"
require "sirena/transform/quadrant"
require "sirena/parser/quadrant"

RSpec.describe Sirena::Renderer::QuadrantRenderer do
  let(:renderer) { described_class.new }

  describe "#render" do
    it "renders a simple quadrant chart to SVG" do
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

      parser = Sirena::Parser::QuadrantParser.new
      diagram = parser.parse(source)

      transform = Sirena::Transform::QuadrantTransform.new
      graph = transform.to_graph(diagram)

      svg = renderer.render(graph)

      expect(svg).to be_a(Sirena::Svg::Document)
      expect(svg.to_xml).to include("Product Analysis")
      expect(svg.to_xml).to include("<svg")
    end

    it "renders quadrant grid with colored backgrounds" do
      source = <<~QUADRANT
        quadrantChart
          x-axis Left --> Right
          y-axis Bottom --> Top
          quadrant-1 Q1
          quadrant-2 Q2
          quadrant-3 Q3
          quadrant-4 Q4
      QUADRANT

      parser = Sirena::Parser::QuadrantParser.new
      diagram = parser.parse(source)

      transform = Sirena::Transform::QuadrantTransform.new
      graph = transform.to_graph(diagram)

      svg = renderer.render(graph)
      xml = svg.to_xml

      # Should contain four quadrant rectangles
      expect(xml.scan(/<rect/).length).to be >= 4
      expect(xml).to include("fill")
      expect(xml).to include("opacity")
    end

    it "renders axis lines and labels" do
      source = <<~QUADRANT
        quadrantChart
          x-axis Low Cost --> High Cost
          y-axis Low Value --> High Value
      QUADRANT

      parser = Sirena::Parser::QuadrantParser.new
      diagram = parser.parse(source)

      transform = Sirena::Transform::QuadrantTransform.new
      graph = transform.to_graph(diagram)

      svg = renderer.render(graph)
      xml = svg.to_xml

      # Should contain axis lines
      expect(xml).to include("<line")

      # Should contain axis labels
      expect(xml).to include("Low Cost")
      expect(xml).to include("High Cost")
      expect(xml).to include("Low Value")
      expect(xml).to include("High Value")
    end

    it "renders quadrant labels" do
      source = <<~QUADRANT
        quadrantChart
          x-axis Left --> Right
          y-axis Bottom --> Top
          quadrant-1 Invest
          quadrant-2 Evaluate
          quadrant-3 Divest
          quadrant-4 Maintain
      QUADRANT

      parser = Sirena::Parser::QuadrantParser.new
      diagram = parser.parse(source)

      transform = Sirena::Transform::QuadrantTransform.new
      graph = transform.to_graph(diagram)

      svg = renderer.render(graph)
      xml = svg.to_xml

      expect(xml).to include("Invest")
      expect(xml).to include("Evaluate")
      expect(xml).to include("Divest")
      expect(xml).to include("Maintain")
    end

    it "renders data points as circles" do
      source = <<~QUADRANT
        quadrantChart
          x-axis Left --> Right
          y-axis Bottom --> Top
          Point A: [0.3, 0.7]
          Point B: [0.8, 0.4]
          Point C: [0.5, 0.5]
      QUADRANT

      parser = Sirena::Parser::QuadrantParser.new
      diagram = parser.parse(source)

      transform = Sirena::Transform::QuadrantTransform.new
      graph = transform.to_graph(diagram)

      svg = renderer.render(graph)
      xml = svg.to_xml

      # Should contain circle elements for points
      expect(xml).to include("<circle")
      expect(xml.scan(/<circle/).length).to be >= 3

      # Should include point labels
      expect(xml).to include("Point A")
      expect(xml).to include("Point B")
      expect(xml).to include("Point C")
    end

    it "renders points with custom styling" do
      source = <<~QUADRANT
        quadrantChart
          x-axis Left --> Right
          y-axis Bottom --> Top
          Product A: [0.5, 0.5] radius: 10, color: #ff0000
      QUADRANT

      parser = Sirena::Parser::QuadrantParser.new
      diagram = parser.parse(source)

      transform = Sirena::Transform::QuadrantTransform.new
      graph = transform.to_graph(diagram)

      svg = renderer.render(graph)
      xml = svg.to_xml

      # Should contain styled circle
      expect(xml).to include("<circle")
      expect(xml).to include("r=\"10")
      expect(xml).to include("#ff0000")
    end

    it "calculates SVG coordinates correctly" do
      source = <<~QUADRANT
        quadrantChart
          x-axis Left --> Right
          y-axis Bottom --> Top
          Center: [0.5, 0.5]
      QUADRANT

      parser = Sirena::Parser::QuadrantParser.new
      diagram = parser.parse(source)

      transform = Sirena::Transform::QuadrantTransform.new
      graph = transform.to_graph(diagram)

      # Check that point coordinates are transformed
      point = graph[:points].first
      expect(point[:svg_x]).to be > 0
      expect(point[:svg_y]).to be > 0
      expect(point[:x]).to eq(0.5)
      expect(point[:y]).to eq(0.5)
    end
  end
end