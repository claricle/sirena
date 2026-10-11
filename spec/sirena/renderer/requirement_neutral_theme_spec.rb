# frozen_string_literal: true

require "digest"
require "rexml/document"
require "rexml/xpath"
require "spec_helper"

RSpec.describe Sirena::Renderer::Requirement do
  subject(:xml) { described_class.new(theme: theme).render(scene).to_xml }

  let(:theme) { Sirena::Theme::Registry.get(:default) }
  let(:source) do
    <<~MERMAID
      requirementDiagram
        requirement r {
          id: 1
          text: Need
          risk: high
        }
        requirement plain {
          id: 2
          text: Plain
        }
        element e {
          type: system
        }
        e - satisfies -> r
    MERMAID
  end
  let(:scene) do
    diagram = Sirena::Parser::Requirement.new.parse(source)
    Sirena::Layout::Requirement.new.call(diagram, theme: theme)
  end
  let(:document) { REXML::Document.new(xml) }
  let(:neutral_paint) do
    requirement = REXML::XPath.first(
      document, "//*[@id='requirement-r']/rect"
    )
    plain_header = REXML::XPath.first(
      document, "//*[@id='requirement-plain']/g/rect"
    )
    element = REXML::XPath.first(document, "//*[@id='element-e']/polygon")
    relationship = "//*[@id='relationship-e-r']"
    {
      requirement_fill: requirement.attributes["fill"],
      plain_header_fill: plain_header.attributes["fill"],
      element_fill: element.attributes["fill"],
      relationship_strokes: REXML::XPath
        .match(document, "#{relationship}/*[self::path or self::rect]")
        .map { |shape| shape.attributes["stroke"] },
      relationship_heads: REXML::XPath
        .match(document, "#{relationship}/polygon")
        .map { |head| head.attributes["fill"] },
    }
  end
  let(:risk_paints) do
    requirement = "//*[@id='requirement-r']"
    [
      REXML::XPath.first(document, "#{requirement}/rect")
        .attributes["stroke"],
      REXML::XPath.first(document, "#{requirement}/g/rect")
        .attributes["fill"],
      REXML::XPath.match(document, "#{requirement}/text")
        .map { |text| text.attributes["fill"] }.compact.last,
    ]
  end

  it "preserves the exact default render" do
    expect(Digest::SHA256.hexdigest(xml))
      .to eq("95c1ba8fed62eb7966d49c8c5cd3eb5a849339534472e15b82748e378edcadf8")
  end

  %i[default light dark high_contrast].each do |theme_name|
    context "with the #{theme_name} theme" do
      let(:theme) { Sirena::Theme::Registry.get(theme_name) }

      it "uses the node and edge semantic roles" do
        colors = theme.colors
        expected = [*Array.new(3, colors.node_fill),
                    Array.new(2, colors.edge_color), [colors.edge_color]]
        expect(neutral_paint.values).to eq(expected)
      end

      it "uses the named risk palette" do
        expect(risk_paints)
          .to eq(Array.new(3, theme.colors.requirement_risk_palette.first))
      end
    end
  end

  context "with a custom theme" do
    let(:theme) do
      Sirena::Theme.new(
        colors: Sirena::Theme::ColorPalette.new(
          node_fill: "#123456", edge_color: "#abcdef",
        ),
      )
    end

    it "uses the custom node and edge roles" do
      expected = [*Array.new(3, "#123456"),
                  ["#abcdef", "#abcdef"], ["#abcdef"]]
      expect(neutral_paint.values).to eq(expected)
    end
  end

  context "with a scalar-empty partial theme" do
    let(:theme) do
      Sirena::Theme.new(colors: Sirena::Theme::ColorPalette.new)
    end

    it "leaves absent node and edge paint unset" do
      expect(neutral_paint).to eq(
        requirement_fill: nil, plain_header_fill: nil, element_fill: nil,
        relationship_strokes: [nil, nil],
        relationship_heads: []
      )
    end

    it "retains the diagram-specific risk palette" do
      expect(risk_paints).to eq(Array.new(3, "#ff6b6b"))
    end
  end
end
