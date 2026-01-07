# frozen_string_literal: true

require "spec_helper"
require "sirena/renderer/radar"
require "sirena/transform/radar"
require "sirena/diagram/radar"

RSpec.describe Sirena::Renderer::Radar do
  let(:theme) { Sirena::Theme::Registry.get(:default) }
  let(:renderer) { described_class.new(theme: theme) }

  describe "#render" do
    context "with a simple radar chart" do
      let(:layout) do
        {
          axes: [
            {
              id: "A",
              label: "Axis A",
              angle_degrees: -90,
              angle_radians: -Math::PI / 2,
              end_x: 0,
              end_y: -200,
              label_x: 0,
              label_y: -230,
              index: 0
            },
            {
              id: "B",
              label: "Axis B",
              angle_degrees: 30,
              angle_radians: Math::PI / 6,
              end_x: 173.2,
              end_y: -100,
              label_x: 199.2,
              label_y: -115,
              index: 1
            },
            {
              id: "C",
              label: "Axis C",
              angle_degrees: 150,
              angle_radians: 5 * Math::PI / 6,
              end_x: -173.2,
              end_y: -100,
              label_x: -199.2,
              label_y: -115,
              index: 2
            }
          ],
          curves: [
            {
              id: "curve1",
              label: "Dataset 1",
              points: [
                { axis_id: "A", value: 80, normalized: 0.8, x: 0, y: -160, angle: -Math::PI / 2 },
                { axis_id: "B", value: 70, normalized: 0.7, x: 121.24, y: -70, angle: Math::PI / 6 },
                { axis_id: "C", value: 90, normalized: 0.9, x: -155.88, y: -90, angle: 5 * Math::PI / 6 }
              ]
            }
          ],
          grid_circles: [
            { radius: 40, value: 20, fraction: 0.2 },
            { radius: 80, value: 40, fraction: 0.4 },
            { radius: 120, value: 60, fraction: 0.6 },
            { radius: 160, value: 80, fraction: 0.8 },
            { radius: 200, value: 100, fraction: 1.0 }
          ],
          center_x: 280,
          center_y: 280,
          radius: 200,
          width: 560,
          height: 560,
          min_value: 0,
          max_value: 100
        }
      end

      it "renders an SVG document" do
        svg = renderer.render(layout)
        expect(svg).to be_a(Sirena::Svg::Document)
      end

      it "sets proper document dimensions" do
        svg = renderer.render(layout)
        expect(svg.width).to eq(layout[:width])
        expect(svg.height).to eq(layout[:height])
      end

      it "includes grid circles" do
        svg = renderer.render(layout)
        circles = svg.children.select { |e| e.is_a?(Sirena::Svg::Circle) }
        # Grid circles + data points
        expect(circles.length).to be >= layout[:grid_circles].length
      end

      it "includes axis lines" do
        svg = renderer.render(layout)
        lines = svg.children.select { |e| e.is_a?(Sirena::Svg::Line) }
        expect(lines.length).to eq(layout[:axes].length)
      end

      it "includes axis labels" do
        svg = renderer.render(layout)
        texts = svg.children.select { |e| e.is_a?(Sirena::Svg::Text) }
        # Axis labels + potentially legend labels
        expect(texts.length).to be >= layout[:axes].length
      end

      it "includes data polygons" do
        svg = renderer.render(layout)
        polygons = svg.children.select { |e| e.is_a?(Sirena::Svg::Polygon) }
        expect(polygons.length).to eq(layout[:curves].length)
      end
    end

    context "with multiple datasets" do
      let(:layout) do
        {
          axes: [
            {
              id: "A",
              label: "Skill A",
              angle_degrees: -90,
              angle_radians: -Math::PI / 2,
              end_x: 0,
              end_y: -200,
              label_x: 0,
              label_y: -230,
              index: 0
            },
            {
              id: "B",
              label: "Skill B",
              angle_degrees: 30,
              angle_radians: Math::PI / 6,
              end_x: 173.2,
              end_y: -100,
              label_x: 199.2,
              label_y: -115,
              index: 1
            }
          ],
          curves: [
            {
              id: "team1",
              label: "Team A",
              points: [
                { axis_id: "A", value: 80, normalized: 0.8, x: 0, y: -160, angle: -Math::PI / 2 },
                { axis_id: "B", value: 70, normalized: 0.7, x: 121.24, y: -70, angle: Math::PI / 6 }
              ]
            },
            {
              id: "team2",
              label: "Team B",
              points: [
                { axis_id: "A", value: 60, normalized: 0.6, x: 0, y: -120, angle: -Math::PI / 2 },
                { axis_id: "B", value: 90, normalized: 0.9, x: 155.88, y: -90, angle: Math::PI / 6 }
              ]
            }
          ],
          grid_circles: [
            { radius: 40, value: 20, fraction: 0.2 },
            { radius: 80, value: 40, fraction: 0.4 },
            { radius: 120, value: 60, fraction: 0.6 },
            { radius: 160, value: 80, fraction: 0.8 },
            { radius: 200, value: 100, fraction: 1.0 }
          ],
          center_x: 280,
          center_y: 280,
          radius: 200,
          width: 560,
          height: 560,
          min_value: 0,
          max_value: 100
        }
      end

      it "renders multiple data polygons" do
        svg = renderer.render(layout)
        polygons = svg.children.select { |e| e.is_a?(Sirena::Svg::Polygon) }
        expect(polygons.length).to eq(2)
      end

      it "applies different colors to different datasets" do
        svg = renderer.render(layout)
        polygons = svg.children.select { |e| e.is_a?(Sirena::Svg::Polygon) }
        colors = polygons.map(&:stroke).uniq
        expect(colors.length).to eq(2)
      end

      it "includes legend for multiple datasets" do
        svg = renderer.render(layout)
        texts = svg.children.select { |e| e.is_a?(Sirena::Svg::Text) }
        # Should include axis labels + legend labels
        legend_texts = texts.select { |t| t.content == "Team A" || t.content == "Team B" }
        expect(legend_texts.length).to eq(2)
      end
    end

    context "with empty layout" do
      let(:layout) do
        {
          axes: [],
          curves: [],
          grid_circles: [],
          center_x: 80,
          center_y: 80,
          radius: 200,
          width: 160,
          height: 160,
          min_value: 0,
          max_value: 0
        }
      end

      it "renders without errors" do
        expect { renderer.render(layout) }.not_to raise_error
      end

      it "returns a valid SVG document" do
        svg = renderer.render(layout)
        expect(svg).to be_a(Sirena::Svg::Document)
      end
    end

    context "with legend disabled" do
      let(:layout) do
        {
          axes: [
            {
              id: "A",
              label: "Axis A",
              angle_degrees: -90,
              angle_radians: -Math::PI / 2,
              end_x: 0,
              end_y: -200,
              label_x: 0,
              label_y: -230,
              index: 0
            }
          ],
          curves: [
            {
              id: "curve1",
              label: "Dataset 1",
              points: [
                { axis_id: "A", value: 80, normalized: 0.8, x: 0, y: -160, angle: -Math::PI / 2 }
              ]
            }
          ],
          grid_circles: [
            { radius: 200, value: 100, fraction: 1.0 }
          ],
          center_x: 280,
          center_y: 280,
          radius: 200,
          width: 560,
          height: 560,
          min_value: 0,
          max_value: 100,
          options: { show_legend: false }
        }
      end

      it "does not render legend when disabled" do
        svg = renderer.render(layout)
        texts = svg.children.select { |e| e.is_a?(Sirena::Svg::Text) }
        legend_texts = texts.select { |t| t.content == "Dataset 1" }
        expect(legend_texts.length).to eq(0)
      end
    end
  end
end