# frozen_string_literal: true

require "spec_helper"
require "sirena/renderer/packet"
require "sirena/layout/packet"
require "sirena/diagram/packet"

RSpec.describe Sirena::Renderer::Packet do
  let(:renderer) { described_class.new }
  let(:title) { nil }
  let(:fields) { [] }
  let(:source) do
    lines = ["packet-beta"]
    lines << "  title #{title}" if title
    fields.each do |first, last, label|
      lines << %(  #{first}-#{last}: "#{label}")
    end
    lines.join("\n")
  end
  let(:layout) do
    diagram = Sirena::Parser::Packet.new.parse(source)
    Sirena::Layout::Packet.new.call(diagram)
  end

  def text_content(text)
    Array(text.content).join
  end

  describe "#render" do
    it "refuses legacy Hash geometry at the typed Scene boundary" do
      expect { renderer.render(fields: [], row_count: 0, title: nil) }
        .to raise_error(NoMethodError)
    end

    context "with a simple packet" do
      let(:title) { "Hello world" }
      let(:fields) { [[0, 10, "hello"]] }

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

      it "places the block where mmdc does" do
        rect = renderer.render(layout).children.grep(Sirena::Svg::Rect).first
        expect([rect.x, rect.y, rect.width, rect.height])
          .to eq([1.0, 15.0, 347.0, 32.0])
      end

      it "places the first and last bit numbers where mmdc does" do
        texts = renderer.render(layout).children.grep(Sirena::Svg::Text)
        numbers = texts.select { |t| text_content(t).match?(/\A\d+\z/) }
        expect(numbers.map { |t| [text_content(t), t.x, t.y] })
          .to eq([["0", 1.0, 13.0], ["10", 348.0, 13.0]])
      end
    end

    context "with multiple fields" do
      let(:fields) do
        [[0, 7, "Source Port"], [8, 15, "Destination Port"],
         [16, 31, "Sequence Number"]]
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
      let(:fields) { [[0, 31, "Field 1"], [32, 63, "Field 2"]] }

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

    context "with an empty Scene" do
      it "renders without errors" do
        expect { renderer.render(layout) }.not_to raise_error
      end

      it "returns a valid SVG document" do
        svg = renderer.render(layout)
        expect(svg).to be_a(Sirena::Svg::Document)
      end
    end

    context "with field spanning multiple rows" do
      let(:fields) do
        [[0, 15, "Short Field"], [16, 47, "Long Field"]]
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
