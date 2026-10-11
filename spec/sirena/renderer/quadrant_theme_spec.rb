# frozen_string_literal: true

require "digest"
require "rexml/document"
require "rexml/xpath"
require "spec_helper"
require "sirena/layout/quadrant"
require "sirena/parser/quadrant"
require "sirena/renderer/quadrant"

RSpec.describe Sirena::Renderer::Quadrant do
  subject(:svg) { described_class.new(theme: theme).render(scene) }

  let(:theme) { Sirena::Theme::Registry.get(:default) }
  let(:scene) do
    diagram = Sirena::Parser::Quadrant.new.parse(source)
    Sirena::Layout::Quadrant.new.to_graph(diagram)
  end
  let(:paint_summary) do
    document = REXML::Document.new(svg.to_xml)
    circles = REXML::XPath.match(document, "//circle")
    texts = REXML::XPath.match(document, "//text")
    {
      circles: circles.map { |circle| element_paint(circle) },
      text_fills: texts.map { |text| text.attributes["fill"] }.uniq,
      quadrant_fills: attributes(document, "quadrant", "rect", "fill"),
      border_strokes: attributes(document, "border", "line", "stroke").uniq,
    }
  end

  %i[default light dark high_contrast].each do |theme_name|
    context "with the #{theme_name} theme" do
      let(:theme) { Sirena::Theme::Registry.get(theme_name) }

      it "uses semantic roles for point and text paint" do
        expect(paint_summary.slice(:circles, :text_fills))
          .to eq(expected_semantic_paint(theme.colors))
      end

      it "uses the named quadrant palette" do
        expect(paint_summary.fetch(:quadrant_fills))
          .to eq(theme.colors.quadrant_palette)
      end

      it "uses the quadrant grid role for every border line" do
        expect(paint_summary.fetch(:border_strokes))
          .to eq([theme.colors.quadrant_grid_line])
      end
    end
  end

  it "preserves the default SVG bytes" do
    expect(Digest::SHA256.hexdigest(svg.to_xml))
      .to eq("1ff4b4a6da5843a1289ad15ac9e9c973e62b4e76a2884a13e89a003d8e028194")
  end

  context "with a scalar-empty partial theme" do
    let(:theme) do
      Sirena::Theme.new(
        colors: Sirena::Theme::ColorPalette.new,
        typography: Sirena::Theme::Typography.new,
      )
    end

    it "leaves absent point and text roles unpainted" do
      expect(paint_summary.slice(:circles, :text_fills)).to eq(
        circles: Array.new(4, [nil, nil]), text_fills: [nil],
      )
    end

    it "retains categorical fills and leaves the absent grid role unpainted" do
      expect(paint_summary.slice(:quadrant_fills, :border_strokes)).to eq(
        quadrant_fills: %w[#ECECFF #f1f1ff #f6f6ff #fbfbff],
        border_strokes: [nil],
      )
    end

    it "keeps an explicit point colour ahead of the absent theme role" do
      scene.points.first.color = "#123456"

      expect(paint_summary.fetch(:circles).first.first).to eq("#123456")
    end
  end

  context "with a custom quadrant grid role" do
    let(:theme) do
      Sirena::Theme.new(
        colors: Sirena::Theme::ColorPalette.new(
          quadrant_grid_line: "#123456",
        ),
      )
    end

    it "uses the supplied border paint" do
      expect(paint_summary.fetch(:border_strokes)).to eq(["#123456"])
    end
  end

  def source
    <<~MERMAID
      quadrantChart
      x-axis Left --> Right
      y-axis Bottom --> Top
      quadrant-1 Q1
      quadrant-2 Q2
      quadrant-3 Q3
      quadrant-4 Q4
      P1: [0.75, 0.75]
      P2: [0.25, 0.75]
      P3: [0.25, 0.25]
      P4: [0.75, 0.25]
    MERMAID
  end

  def element_paint(element)
    [element.attributes["fill"], element.attributes["stroke"]]
  end

  def attributes(document, group, element, attribute)
    path = "//g[@class='#{group}']/#{element}"
    REXML::XPath.match(document, path).map do |item|
      item.attributes[attribute]
    end
  end

  def expected_semantic_paint(colors)
    fills = [colors.primary, colors.secondary, colors.accent, colors.success]
    {
      circles: fills.map { |fill| [fill, colors.node_stroke] },
      text_fills: [colors.label_text],
    }
  end
end
