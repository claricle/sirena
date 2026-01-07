# frozen_string_literal: true

require "spec_helper"
require "sirena/renderer/mindmap"
require "sirena/transform/mindmap"
require "sirena/diagram/mindmap"

RSpec.describe Sirena::Renderer::Mindmap do
  let(:theme) { Sirena::Theme::Registry.get(:default) }
  let(:renderer) { described_class.new(theme: theme) }

  describe "#render" do
    context "with a simple mindmap" do
      let(:layout) do
        {
          nodes: [
            {
              id: "node-0",
              content: "Root",
              x: 200,
              y: 20,
              width: 100,
              height: 40,
              level: 0,
              shape: "default",
              icon: nil,
              classes: []
            },
            {
              id: "node-1",
              content: "Child 1",
              x: 150,
              y: 140,
              width: 100,
              height: 40,
              level: 1,
              shape: "default",
              icon: nil,
              classes: [],
              parent_id: "node-0"
            },
            {
              id: "node-2",
              content: "Child 2",
              x: 250,
              y: 140,
              width: 100,
              height: 40,
              level: 1,
              shape: "default",
              icon: nil,
              classes: [],
              parent_id: "node-0"
            }
          ],
          connections: [
            {
              from: "node-0",
              to: "node-1",
              type: :parent_child
            },
            {
              from: "node-0",
              to: "node-2",
              type: :parent_child
            }
          ],
          width: 400,
          height: 200,
          root: {
            id: "node-0",
            content: "Root",
            x: 200,
            y: 20,
            width: 100,
            height: 40,
            level: 0,
            shape: "default"
          }
        }
      end

      it "renders an SVG document" do
        svg = renderer.render(layout)
        expect(svg).to be_a(Sirena::Svg::Document)
      end

      it "sets proper document dimensions" do
        svg = renderer.render(layout)
        expect(svg.width).to be > layout[:width]
        expect(svg.height).to be > layout[:height]
      end

      it "includes nodes as shapes" do
        svg = renderer.render(layout)
        shapes = svg.children.select do |e|
          e.is_a?(Sirena::Svg::Rect) ||
            e.is_a?(Sirena::Svg::Circle) ||
            e.is_a?(Sirena::Svg::Polygon)
        end
        expect(shapes.length).to be >= layout[:nodes].length
      end

      it "includes text labels for nodes" do
        svg = renderer.render(layout)
        texts = svg.children.select { |e| e.is_a?(Sirena::Svg::Text) }
        expect(texts.length).to eq(layout[:nodes].length)
      end

      it "includes connection paths" do
        svg = renderer.render(layout)
        paths = svg.children.select { |e| e.is_a?(Sirena::Svg::Path) }
        expect(paths.length).to eq(layout[:connections].length)
      end
    end

    context "with different node shapes" do
      let(:layout) do
        {
          nodes: [
            {
              id: "node-0",
              content: "Circle",
              x: 200,
              y: 20,
              width: 80,
              height: 80,
              level: 0,
              shape: "circle",
              icon: nil,
              classes: []
            },
            {
              id: "node-1",
              content: "Square",
              x: 100,
              y: 140,
              width: 100,
              height: 40,
              level: 1,
              shape: "square",
              icon: nil,
              classes: []
            },
            {
              id: "node-2",
              content: "Hexagon",
              x: 300,
              y: 140,
              width: 100,
              height: 40,
              level: 1,
              shape: "hexagon",
              icon: nil,
              classes: []
            }
          ],
          connections: [],
          width: 400,
          height: 200,
          root: nil
        }
      end

      it "renders circle nodes" do
        svg = renderer.render(layout)
        circles = svg.children.select { |e| e.is_a?(Sirena::Svg::Circle) }
        expect(circles.length).to be >= 1
      end

      it "renders square nodes" do
        svg = renderer.render(layout)
        rects = svg.children.select { |e| e.is_a?(Sirena::Svg::Rect) }
        expect(rects.length).to be >= 1
      end

      it "renders hexagon nodes" do
        svg = renderer.render(layout)
        polygons = svg.children.select { |e| e.is_a?(Sirena::Svg::Polygon) }
        expect(polygons.length).to be >= 1
      end
    end

    context "with cloud and bang shapes" do
      let(:layout) do
        {
          nodes: [
            {
              id: "node-0",
              content: "Cloud",
              x: 200,
              y: 20,
              width: 100,
              height: 60,
              level: 0,
              shape: "cloud",
              icon: nil,
              classes: []
            },
            {
              id: "node-1",
              content: "Bang",
              x: 200,
              y: 140,
              width: 100,
              height: 60,
              level: 1,
              shape: "bang",
              icon: nil,
              classes: []
            }
          ],
          connections: [],
          width: 300,
          height: 220,
          root: nil
        }
      end

      it "renders cloud shapes using paths" do
        svg = renderer.render(layout)
        paths = svg.children.select { |e| e.is_a?(Sirena::Svg::Path) }
        expect(paths.length).to be >= 1
      end

      it "renders bang shapes using paths" do
        svg = renderer.render(layout)
        paths = svg.children.select { |e| e.is_a?(Sirena::Svg::Path) }
        expect(paths.length).to be >= 1
      end
    end

    context "with multi-level hierarchy" do
      let(:layout) do
        {
          nodes: [
            {
              id: "node-0",
              content: "Root",
              x: 250,
              y: 20,
              width: 100,
              height: 40,
              level: 0,
              shape: "circle",
              icon: nil,
              classes: []
            },
            {
              id: "node-1",
              content: "Level 1 - A",
              x: 150,
              y: 140,
              width: 100,
              height: 40,
              level: 1,
              shape: "default",
              icon: nil,
              classes: [],
              parent_id: "node-0"
            },
            {
              id: "node-2",
              content: "Level 1 - B",
              x: 350,
              y: 140,
              width: 100,
              height: 40,
              level: 1,
              shape: "default",
              icon: nil,
              classes: [],
              parent_id: "node-0"
            },
            {
              id: "node-3",
              content: "Level 2",
              x: 150,
              y: 260,
              width: 100,
              height: 40,
              level: 2,
              shape: "square",
              icon: nil,
              classes: [],
              parent_id: "node-1"
            }
          ],
          connections: [
            { from: "node-0", to: "node-1", type: :parent_child },
            { from: "node-0", to: "node-2", type: :parent_child },
            { from: "node-1", to: "node-3", type: :parent_child }
          ],
          width: 500,
          height: 320,
          root: nil
        }
      end

      it "applies different colors based on level" do
        svg = renderer.render(layout)
        # Level 0 should be one color, level 1 another, level 2 another
        shapes = svg.children.select do |e|
          e.is_a?(Sirena::Svg::Rect) ||
            e.is_a?(Sirena::Svg::Circle) ||
            e.is_a?(Sirena::Svg::Polygon)
        end
        stroke_colors = shapes.map(&:stroke).uniq
        expect(stroke_colors.length).to be >= 2
      end

      it "renders all levels" do
        svg = renderer.render(layout)
        texts = svg.children.select { |e| e.is_a?(Sirena::Svg::Text) }
        expect(texts.length).to eq(4)
      end
    end
  end
end