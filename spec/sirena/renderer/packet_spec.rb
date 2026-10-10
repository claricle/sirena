# frozen_string_literal: true

require "spec_helper"
require "sirena/renderer/packet"
require "sirena/layout/packet"
require "sirena/diagram/packet"

RSpec.describe Sirena::Renderer::Packet do
  let(:theme) { Sirena::Theme::Registry.get(:default) }
  let(:renderer) { described_class.new(theme: theme) }

  def text_content(text)
    Array(text.content).join
  end

  describe "#render" do
    context "with a simple packet" do
      let(:layout) do
        {
          fields: [
            {
              label: "hello",
              bit_start: 0,
              bit_end: 10,
            },
          ],
          row_count: 1,
          title: "Hello world",
        }
      end

      it "renders an SVG document" do
        svg = renderer.render(layout)
        expect(svg).to be_a(Sirena::Svg::Document)
      end

      it "sizes the canvas like mmdc's viewBox for the same diagram" do
        svg = renderer.render(layout)
        expect([svg.width, svg.height]).to eq([1026.0, 94.0])
      end

      it "includes title" do
        svg = renderer.render(layout)
        texts = svg.children.grep(Sirena::Svg::Text)
        # `content` is `collection: true`, so read it through Array(...).
        title_texts = texts.select { |t| text_content(t) == "Hello world" }
        expect(title_texts.length).to eq(1)
      end

      it "includes field rectangles" do
        svg = renderer.render(layout)
        rects = svg.children.grep(Sirena::Svg::Rect)
        expect(rects.length).to be >= 1
      end

      it "includes field labels" do
        svg = renderer.render(layout)
        texts = svg.children.grep(Sirena::Svg::Text)
        field_texts = texts.select { |t| Array(t.content).join == "hello" }
        expect(field_texts.length).to eq(1)
      end

      it "places the block and its bit numbers where mmdc does" do
        svg = renderer.render(layout)
        rect = svg.children.grep(Sirena::Svg::Rect).first
        texts = svg.children.grep(Sirena::Svg::Text)
        numbers = texts.select { |t| text_content(t).match?(/\A\d+\z/) }
        expect([[rect.x, rect.y, rect.width, rect.height],
                numbers.map { |t| [text_content(t), t.x, t.y] }])
          .to eq([[1.0, 15.0, 347.0, 32.0],
                  [["0", 1.0, 13.0], ["10", 348.0, 13.0]]])
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
            },
            {
              label: "Destination Port",
              bit_start: 8,
              bit_end: 15,
            },
            {
              label: "Sequence Number",
              bit_start: 16,
              bit_end: 31,
            },
          ],
          row_count: 1,
          title: nil,
        }
      end

      it "renders all fields" do
        svg = renderer.render(layout)
        rects = svg.children.grep(Sirena::Svg::Rect)
        expect(rects.length).to be >= 3
      end

      it "includes all field labels" do
        svg = renderer.render(layout)
        texts = svg.children.grep(Sirena::Svg::Text)
        contents = texts.map { |t| text_content(t) }
        expect(contents).to include("Source Port", "Destination Port",
                                    "Sequence Number")
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
            },
            {
              label: "Field 2",
              bit_start: 32,
              bit_end: 63,
            },
          ],
          row_count: 2,
          title: nil,
        }
      end

      it "renders fields in different rows" do
        svg = renderer.render(layout)
        rects = svg.children.grep(Sirena::Svg::Rect)
        expect(rects.length).to be >= 2
      end

      it "numbers only the first and last bit of each block, one row down" do
        svg = renderer.render(layout)
        texts = svg.children.grep(Sirena::Svg::Text)
        bit_markers = texts.select { |t| text_content(t).match?(/\A\d+\z/) }
        expect(bit_markers.map { |t| [text_content(t), t.y] })
          .to eq([["0", 13.0], ["31", 13.0], ["32", 60.0], ["63", 60.0]])
      end
    end

    context "with empty layout" do
      let(:layout) do
        {
          fields: [],
          row_count: 0,
          title: nil,
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
              is_continuation: false,
              is_final: true,
            },
            {
              label: "Long Field",
              bit_start: 16,
              bit_end: 31,
              is_continuation: false,
              is_final: false,
            },
            {
              label: "Long Field",
              bit_start: 32,
              bit_end: 47,
              is_continuation: true,
              is_final: true,
            },
          ],
          row_count: 2,
          title: nil,
        }
      end

      it "renders all field segments" do
        svg = renderer.render(layout)
        rects = svg.children.grep(Sirena::Svg::Rect)
        expect(rects.length).to be >= 3
      end

      it "includes labels for all segments" do
        svg = renderer.render(layout)
        texts = svg.children.grep(Sirena::Svg::Text)
        long_field_texts = texts.select { |t| text_content(t) == "Long Field" }
        expect(long_field_texts.length).to eq(2)
      end
    end
  end
end
