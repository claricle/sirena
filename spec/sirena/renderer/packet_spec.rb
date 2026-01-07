# frozen_string_literal: true

require "spec_helper"
require "sirena/renderer/packet"
require "sirena/transform/packet"
require "sirena/diagram/packet"

RSpec.describe Sirena::Renderer::Packet do
  let(:theme) { Sirena::Theme::Registry.get(:default) }
  let(:renderer) { described_class.new(theme: theme) }

  describe "#render" do
    context "with a simple packet" do
      let(:layout) do
        {
          fields: [
            {
              label: "hello",
              bit_start: 0,
              bit_end: 10,
              x: 40,
              y: 70,
              width: 330,
              height: 40,
              row: 0,
              start_col: 0,
              end_col: 10
            }
          ],
          row_count: 1,
          bits_per_row: 32,
          cell_width: 30,
          cell_height: 40,
          padding: 40,
          header_height: 30,
          title_height: 40,
          title_margin: 20,
          width: 1040,
          height: 210,
          title: "Hello world"
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
        title_texts = texts.select { |t| t.content == "Hello world" }
        expect(title_texts.length).to eq(1)
      end

      it "includes field rectangles" do
        svg = renderer.render(layout)
        rects = svg.children.select { |e| e.is_a?(Sirena::Svg::Rect) }
        expect(rects.length).to be >= 1
      end

      it "includes field labels" do
        svg = renderer.render(layout)
        texts = svg.children.select { |e| e.is_a?(Sirena::Svg::Text) }
        field_texts = texts.select { |t| t.content == "hello" }
        expect(field_texts.length).to eq(1)
      end

      it "includes grid lines" do
        svg = renderer.render(layout)
        lines = svg.children.select { |e| e.is_a?(Sirena::Svg::Line) }
        # Should have both vertical and horizontal grid lines
        expect(lines.length).to be > 0
      end
    end

    context "with multiple fields" do
      let(:layout) do
        {
          fields: [
            {
              label: "Source Port",
              bit_start: 0,
              bit_end: 7,
              x: 40,
              y: 70,
              width: 240,
              height: 40,
              row: 0,
              start_col: 0,
              end_col: 7
            },
            {
              label: "Destination Port",
              bit_start: 8,
              bit_end: 15,
              x: 280,
              y: 70,
              width: 240,
              height: 40,
              row: 0,
              start_col: 8,
              end_col: 15
            },
            {
              label: "Sequence Number",
              bit_start: 16,
              bit_end: 31,
              x: 520,
              y: 70,
              width: 480,
              height: 40,
              row: 0,
              start_col: 16,
              end_col: 31
            }
          ],
          row_count: 1,
          bits_per_row: 32,
          cell_width: 30,
          cell_height: 40,
          padding: 40,
          header_height: 30,
          title_height: 0,
          title_margin: 0,
          width: 1040,
          height: 150,
          title: nil
        }
      end

      it "renders all fields" do
        svg = renderer.render(layout)
        rects = svg.children.select { |e| e.is_a?(Sirena::Svg::Rect) }
        expect(rects.length).to be >= 3
      end

      it "includes all field labels" do
        svg = renderer.render(layout)
        texts = svg.children.select { |e| e.is_a?(Sirena::Svg::Text) }
        expect(texts.any? { |t| t.content == "Source Port" }).to be true
        expect(texts.any? { |t| t.content == "Destination Port" }).to be true
        expect(texts.any? { |t| t.content == "Sequence Number" }).to be true
      end
    end

    context "with multi-row packet" do
      let(:layout) do
        {
          fields: [
            {
              label: "Field 1",
              bit_start: 0,
              bit_end: 31,
              x: 40,
              y: 70,
              width: 960,
              height: 40,
              row: 0,
              start_col: 0,
              end_col: 31
            },
            {
              label: "Field 2",
              bit_start: 32,
              bit_end: 63,
              x: 40,
              y: 110,
              width: 960,
              height: 40,
              row: 1,
              start_col: 0,
              end_col: 31
            }
          ],
          row_count: 2,
          bits_per_row: 32,
          cell_width: 30,
          cell_height: 40,
          padding: 40,
          header_height: 30,
          title_height: 0,
          title_margin: 0,
          width: 1040,
          height: 190,
          title: nil
        }
      end

      it "renders fields in different rows" do
        svg = renderer.render(layout)
        rects = svg.children.select { |e| e.is_a?(Sirena::Svg::Rect) }
        expect(rects.length).to be >= 2
      end

      it "renders bit markers for all rows" do
        svg = renderer.render(layout)
        texts = svg.children.select { |e| e.is_a?(Sirena::Svg::Text) }
        # Should have bit markers for bits 0-63 (2 rows of 32 bits)
        bit_markers = texts.select { |t| t.content.match?(/^\d+$/) }
        expect(bit_markers.length).to eq(64)
      end
    end

    context "with empty layout" do
      let(:layout) do
        {
          fields: [],
          row_count: 0,
          bits_per_row: 32,
          cell_width: 30,
          cell_height: 40,
          padding: 40,
          header_height: 30,
          title_height: 0,
          title_margin: 0,
          width: 80,
          height: 80,
          title: nil
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

    context "with field spanning multiple rows" do
      let(:layout) do
        {
          fields: [
            {
              label: "Short Field",
              bit_start: 0,
              bit_end: 15,
              x: 40,
              y: 70,
              width: 480,
              height: 40,
              row: 0,
              start_col: 0,
              end_col: 15,
              is_continuation: false,
              is_final: true
            },
            {
              label: "Long Field",
              bit_start: 16,
              bit_end: 31,
              x: 520,
              y: 70,
              width: 480,
              height: 40,
              row: 0,
              start_col: 16,
              end_col: 31,
              is_continuation: false,
              is_final: false
            },
            {
              label: "Long Field",
              bit_start: 32,
              bit_end: 47,
              x: 40,
              y: 110,
              width: 480,
              height: 40,
              row: 1,
              start_col: 0,
              end_col: 15,
              is_continuation: true,
              is_final: true
            }
          ],
          row_count: 2,
          bits_per_row: 32,
          cell_width: 30,
          cell_height: 40,
          padding: 40,
          header_height: 30,
          title_height: 0,
          title_margin: 0,
          width: 1040,
          height: 190,
          title: nil
        }
      end

      it "renders all field segments" do
        svg = renderer.render(layout)
        rects = svg.children.select { |e| e.is_a?(Sirena::Svg::Rect) }
        expect(rects.length).to be >= 3
      end

      it "includes labels for all segments" do
        svg = renderer.render(layout)
        texts = svg.children.select { |e| e.is_a?(Sirena::Svg::Text) }
        long_field_texts = texts.select { |t| t.content == "Long Field" }
        expect(long_field_texts.length).to eq(2)
      end
    end
  end
end