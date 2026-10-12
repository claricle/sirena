# frozen_string_literal: true

require "digest"
require "rexml/document"
require "rexml/xpath"
require "spec_helper"

RSpec.describe Sirena::Renderer::Mindmap do
  subject(:xml) { described_class.new(theme: theme).render(scene).to_xml }

  let(:theme) { Sirena::Theme::Registry.get(:default) }
  let(:scene) do
    diagram = Sirena::Parser::Mindmap.new.parse(
      "mindmap\n  root((Root))\n    child[Child]\n",
    )
    Sirena::Layout::Mindmap.new.call(diagram, theme: theme)
  end
  let(:document) { REXML::Document.new(xml) }
  let(:text_fills) do
    REXML::XPath.match(document, "//text")
      .map { |text| text.attributes["fill"] }.uniq
  end
  let(:node_strokes) do
    REXML::XPath.match(document, "//*[@class='node mindmap-node']/*[1]")
      .map { |shape| shape.attributes["stroke"] }
  end

  it "preserves the exact default render" do
    expect(Digest::SHA256.hexdigest(xml))
      .to eq("4fb371d18b73ed2d5a268983cc5d807c10461251d241882c00866e72ded80a40")
  end

  %i[default light dark high_contrast].each do |theme_name|
    context "with the #{theme_name} theme" do
      let(:theme) { Sirena::Theme::Registry.get(theme_name) }

      it "uses the semantic label role" do
        expect(text_fills).to eq([theme.colors.label_text])
      end

      it "uses the named level palette" do
        expect(node_strokes).to eq(theme.colors.mindmap_palette.first(2))
      end
    end
  end

  context "with a custom theme" do
    let(:theme) do
      Sirena::Theme.new(
        colors: Sirena::Theme::ColorPalette.new(label_text: "#123456"),
      )
    end

    it "uses the custom label role while retaining the level palette" do
      expect([text_fills, node_strokes])
        .to eq([["#123456"], %w[#007bff #6c757d]])
    end
  end

  context "with a scalar-empty partial theme" do
    let(:theme) do
      Sirena::Theme.new(colors: Sirena::Theme::ColorPalette.new)
    end

    it "leaves absent label paint unset while retaining the level palette" do
      expect([text_fills, node_strokes])
        .to eq([[nil], %w[#007bff #6c757d]])
    end
  end
end
