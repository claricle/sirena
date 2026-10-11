# frozen_string_literal: true

require "digest"
require "rexml/document"
require "rexml/xpath"
require "spec_helper"

RSpec.describe Sirena::Renderer::Requirement do
  subject(:xml) { described_class.new(theme: theme).render(scene).to_xml }

  let(:theme) { Sirena::Theme::Registry.get(:default) }
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
        .filter_map { |text| text.attributes["fill"] }.last,
    ]
  end

  def specific_role_paint
    plain = "//*[@id='requirement-plain']"
    element = "//*[@id='element-e']"
    {
      requirement_border: attribute_at("#{plain}/rect", "stroke"),
      element_border: attribute_at("#{element}/polygon", "stroke"),
      ordinary_text: ordinary_text_fills(plain, element),
      detail_text: detail_text_fill(element),
    }
  end

  def ordinary_text_fills(plain, element)
    ["#{plain}/g/text", "#{plain}/text", "#{element}/text",
     "//*[@id='relationship-e-r']/text"]
      .map { |path| attribute_at(path, "fill") }.uniq
  end

  def detail_text_fill(element)
    REXML::XPath.match(document, "#{element}/text")
      .find { |text| text.text.start_with?("Type:") }
      .attributes["fill"]
  end

  def attribute_at(path, name)
    REXML::XPath.first(document, path).attributes[name]
  end

  def builtin_specific_role_paint
    colors = theme.colors
    {
      requirement_border: colors.requirement_box_border,
      element_border: colors.requirement_element_border,
      ordinary_text: [colors.requirement_text],
      detail_text: colors.requirement_detail_text,
    }
  end

  def source
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

  it "preserves the exact default render" do
    expect(Digest::SHA256.hexdigest(xml))
      .to eq("3892c1ce3227f2a82e207717d39830681e9ee2900083bb54eb6c68787530f833")
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

      it "uses the requirement-specific neutral roles" do
        expect(specific_role_paint).to eq(builtin_specific_role_paint)
      end

      it "uses the unknown-risk border role" do
        renderer = described_class.new(theme: theme)
        expect(renderer.send(:risk_color, "unknown"))
          .to eq(theme.colors.requirement_unknown_risk_border)
      end
    end
  end

  context "with a custom theme" do
    let(:theme) do
      Sirena::Theme.new(
        colors: Sirena::Theme::ColorPalette.new(
          node_fill: "#123456", edge_color: "#abcdef",
          requirement_box_border: "#111111",
          requirement_element_border: "#222222",
          requirement_text: "#333333", requirement_detail_text: "#444444",
          requirement_unknown_risk_border: "#555555"
        ),
      )
    end

    it "uses the custom node and edge roles" do
      expected = [*Array.new(3, "#123456"),
                  ["#abcdef", "#abcdef"], ["#abcdef"]]
      expect(neutral_paint.values).to eq(expected)
    end

    it "uses the custom requirement-specific roles" do
      expect(specific_role_paint).to eq(
        requirement_border: "#111111", element_border: "#222222",
        ordinary_text: ["#333333"], detail_text: "#444444"
      )
    end

    it "uses the custom unknown-risk border role" do
      expect(described_class.new(theme: theme).send(:risk_color, "unknown"))
        .to eq("#555555")
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

    it "leaves absent requirement-specific roles unpainted" do
      expect(specific_role_paint).to eq(
        requirement_border: nil, element_border: nil,
        ordinary_text: [nil], detail_text: nil
      )
    end

    it "leaves the absent unknown-risk border role unpainted" do
      expect(described_class.new(theme: theme).send(:risk_color, "unknown"))
        .to be_nil
    end
  end
end
