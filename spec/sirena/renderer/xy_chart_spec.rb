# frozen_string_literal: true

require "spec_helper"
require "sirena/renderer/xy_chart"
require "sirena/transform/xy_chart"
require "sirena/diagram/xy_chart"

RSpec.describe Sirena::Renderer::XYChart do
  let(:theme) { Sirena::Theme::Registry.get(:default) }
  let(:renderer) { described_class.new(theme: theme) }

  describe "#render" do
    context "with a simple XY chart" do
      let(:layout) do
        {
          width: 800,
          height: 500,
          plot_x: 100,
          plot_y: 80,
          plot_width: 640,
          plot_height: 340,
          title: "Sales Revenue",
          x_axis: {
            label: "Month",
            type: :categorical,
            positions: [
              { label: "jan", position: 106.67, index: 0 },
              { label: "feb", position: 320.0, index: 1 },
              { label: "mar", position: 533.33, index: 2 }
            ],
            min: 0,
            max: 2,
            width: 640
          },
          y_axis: {
            label: "Revenue ($)",
            min: 0,
            max: 100,
            height: 340,
            scale: 3.4
          },
          datasets: [
            {
              id: "dataset_0",
              label: "Line",
              chart_type: :line,
              points: [
                { x: 106.67, y: 306.0, value: 10.0, index: 0 },
                { x: 320.0, y: 272.0, value: 20.0, index: 1 },
                { x: 533.33, y: 238.0, value: 30.0, index: 2 }
              ]
            }
          ]
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

      it "includes title" do
        svg = renderer.render(layout)
        texts = svg.children.select { |e| e.is_a?(Sirena::Svg::Text) }
        title_text = texts.find { |t| t.content == "Sales Revenue" }
        expect(title_text).not_to be_nil
      end

      it "includes axis lines" do
        svg = renderer.render(layout)
        lines = svg.children.select { |e| e.is_a?(Sirena::Svg::Line) }
        # Grid lines + X-axis + Y-axis
        expect(lines.length).to be >= 2
      end

      it "includes line chart" do
        svg = renderer.render(layout)
        polylines = svg.children.select { |e| e.is_a?(Sirena::Svg::Polyline) }
        expect(polylines.length).to eq(1)
      end

      it "includes data point markers" do
        svg = renderer.render(layout)
        circles = svg.children.select { |e| e.is_a?(Sirena::Svg::Circle) }
        expect(circles.length).to eq(3)
      end
    end

    context "with bar chart" do
      let(:layout) do
        {
          width: 800,
          height: 500,
          plot_x: 100,
          plot_y: 80,
          plot_width: 640,
          plot_height: 340,
          title: nil,
          x_axis: {
            label: nil,
            type: :categorical,
            positions: [
              { label: "A", position: 106.67, index: 0 },
              { label: "B", position: 320.0, index: 1 }
            ],
            min: 0,
            max: 1,
            width: 640
          },
          y_axis: {
            label: nil,
            min: 0,
            max: 100,
            height: 340,
            scale: 3.4
          },
          datasets: [
            {
              id: "dataset_0",
              label: "Bar",
              chart_type: :bar,
              points: [
                { x: 106.67, y: 272.0, value: 20.0, index: 0 },
                { x: 320.0, y: 238.0, value: 30.0, index: 1 }
              ]
            }
          ]
        }
      end

      it "renders bars" do
        svg = renderer.render(layout)
        rects = svg.children.select { |e| e.is_a?(Sirena::Svg::Rect) }
        # Bars + potentially legend boxes
        expect(rects.length).to be >= 2
      end
    end

    context "with multiple datasets" do
      let(:layout) do
        {
          width: 800,
          height: 500,
          plot_x: 100,
          plot_y: 80,
          plot_width: 640,
          plot_height: 340,
          title: "Sales Data",
          x_axis: {
            label: nil,
            type: :categorical,
            positions: [
              { label: "Q1", position: 160.0, index: 0 },
              { label: "Q2", position: 480.0, index: 1 }
            ],
            min: 0,
            max: 1,
            width: 640
          },
          y_axis: {
            label: nil,
            min: 0,
            max: 100,
            height: 340,
            scale: 3.4
          },
          datasets: [
            {
              id: "dataset_0",
              label: "Series A",
              chart_type: :line,
              points: [
                { x: 160.0, y: 272.0, value: 20.0, index: 0 },
                { x: 480.0, y: 238.0, value: 30.0, index: 1 }
              ]
            },
            {
              id: "dataset_1",
              label: "Series B",
              chart_type: :line,
              points: [
                { x: 160.0, y: 306.0, value: 10.0, index: 0 },
                { x: 480.0, y: 204.0, value: 40.0, index: 1 }
              ]
            }
          ]
        }
      end

      it "renders multiple datasets" do
        svg = renderer.render(layout)
        polylines = svg.children.select { |e| e.is_a?(Sirena::Svg::Polyline) }
        expect(polylines.length).to eq(2)
      end

      it "applies different colors to different datasets" do
        svg = renderer.render(layout)
        polylines = svg.children.select { |e| e.is_a?(Sirena::Svg::Polyline) }
        colors = polylines.map(&:stroke).uniq
        expect(colors.length).to eq(2)
      end

      it "includes legend" do
        svg = renderer.render(layout)
        texts = svg.children.select { |e| e.is_a?(Sirena::Svg::Text) }
        legend_texts = texts.select { |t| t.content == "Series A" || t.content == "Series B" }
        expect(legend_texts.length).to eq(2)
      end
    end
  end
end