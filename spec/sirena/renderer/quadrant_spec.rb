# frozen_string_literal: true

require "spec_helper"
require "sirena/renderer/quadrant"
require "sirena/layout/quadrant"
require "sirena/parser/quadrant"

RSpec.describe Sirena::Renderer::Quadrant, :aggregate_failures do
  let(:renderer) { described_class.new }

  def final_label(text, x_position: 10, y_position: 10)
    Sirena::Layout::Quadrant::Label.new(
      text: text, x: x_position, y: y_position, font_size: 14,
      text_anchor: "middle", baseline: "middle"
    )
  end

  def single_quadrant_scene
    coordinates = { x_position: 25, y_position: 25 }
    legacy_label = final_label("Legacy inference", **coordinates)
    quadrant = Sirena::Layout::Quadrant::Rect.new(
      number: 1, x: 0, y: 0, width: 50, height: 50,
      label: final_label("Attached", x_position: 7, y_position: 9)
    )
    Sirena::Layout::Quadrant::Scene.new(
      width: 100, height: 100, quadrants: [quadrant],
      quadrant_labels: [legacy_label]
    )
  end

  def sparse_quadrant_scene
    source = <<~QUADRANT
      quadrantChart
        quadrant-1 First
        quadrant-3 Third
    QUADRANT
    diagram = Sirena::Parser::Quadrant.new.parse(source)
    Sirena::Layout::Quadrant.new.call(diagram)
  end

  describe "#render" do
    let(:graph) do
      diagram = Sirena::Parser::Quadrant.new.parse(source)
      Sirena::Layout::Quadrant.new.to_graph(diagram)
    end
    let(:xml) { renderer.render(graph).to_xml }

    it "rejects a bare positioned Hash" do
      expect { renderer.render(width: 100, height: 100) }
        .to raise_error(NoMethodError)
    end

    it "renders only the final label attached to each Scene quadrant" do
      xml = renderer.render(single_quadrant_scene).to_xml

      expect(xml).to include(">Attached</text>")
      expect(xml).not_to include("Legacy inference")
    end

    it "receives each label already associated by Layout" do
      labels = sparse_quadrant_scene.quadrants.map do |quadrant|
        quadrant.label&.text
      end

      expect(labels).to eq(["First", nil, "Third", nil])
    end

    context "with a simple quadrant chart" do
      let(:source) do
        <<~QUADRANT
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
      end

      it "renders to an SVG document" do
        expect(renderer.render(graph)).to be_a(Sirena::Svg::Document)
      end

      it "renders the title and the svg element" do
        expect(xml).to include("Product Analysis", "<svg")
      end
    end

    context "with quadrant grid backgrounds" do
      let(:source) do
        <<~QUADRANT
          quadrantChart
            x-axis Left --> Right
            y-axis Bottom --> Top
            quadrant-1 Q1
            quadrant-2 Q2
            quadrant-3 Q3
            quadrant-4 Q4
        QUADRANT
      end

      # mmdc draws four opaque quadrant rectangles, one per g.quadrant
      it "renders four quadrant groups" do
        expect(xml.scan('<g class="quadrant">').length).to eq(4)
      end

      it "fills each quadrant with an opaque rectangle" do
        expect(xml.scan(/<rect fill="#[0-9A-Fa-f]{6}"/).length).to eq(4)
      end

      it "uses no opacity" do
        expect(xml).not_to include("opacity")
      end
    end

    context "with axes" do
      let(:source) do
        <<~QUADRANT
          quadrantChart
            x-axis Low Cost --> High Cost
            y-axis Low Value --> High Value
        QUADRANT
      end

      it "renders axis lines" do
        expect(xml).to include("<line")
      end

      it "renders axis labels" do
        expect(xml).to include("Low Cost", "High Cost",
                               "Low Value", "High Value")
      end
    end

    context "with quadrant labels" do
      let(:source) do
        <<~QUADRANT
          quadrantChart
            x-axis Left --> Right
            y-axis Bottom --> Top
            quadrant-1 Invest
            quadrant-2 Evaluate
            quadrant-3 Divest
            quadrant-4 Maintain
        QUADRANT
      end

      it "renders quadrant labels" do
        expect(xml).to include("Invest", "Evaluate", "Divest", "Maintain")
      end
    end

    context "with data points" do
      let(:source) do
        <<~QUADRANT
          quadrantChart
            x-axis Left --> Right
            y-axis Bottom --> Top
            Point A: [0.3, 0.7]
            Point B: [0.8, 0.4]
            Point C: [0.5, 0.5]
        QUADRANT
      end

      it "renders circle elements for points" do
        expect(xml).to include("<circle")
        expect(xml.scan("<circle").length).to be >= 3
      end

      it "includes the point labels" do
        expect(xml).to include("Point A", "Point B", "Point C")
      end
    end

    context "with custom point styling" do
      let(:source) do
        <<~QUADRANT
          quadrantChart
            x-axis Left --> Right
            y-axis Bottom --> Top
            Product A: [0.5, 0.5] radius: 10, color: #ff0000
        QUADRANT
      end

      it "renders a styled circle" do
        expect(xml).to include("<circle", "r=\"10", "#ff0000")
      end
    end

    context "with a centred point" do
      let(:source) do
        <<~QUADRANT
          quadrantChart
            x-axis Left --> Right
            y-axis Bottom --> Top
            Center: [0.5, 0.5]
        QUADRANT
      end

      it "calculates SVG coordinates correctly" do
        point = graph.points.first

        expect(point.x).to be > 0
        expect(point.y).to be > 0
        expect([point.x, point.y]).to eq([263.0, 237.0])
      end
    end
  end
end
