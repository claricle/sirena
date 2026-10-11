# frozen_string_literal: true

require "digest"
require "rexml/document"
require "spec_helper"

RSpec.describe Sirena::Renderer::Pie do
  let(:source) do
    <<~MERMAID
      pie title Pets
        "Dogs" : 60
        "Cats" : 40
    MERMAID
  end
  let(:palette) { %w[#4472C4 #ED7D31] }

  context "with the default theme" do
    let(:rendering) do
      xml = Sirena.render(source)
      document = REXML::Document.new(xml)
      fills = REXML::XPath.match(document, "//path/@fill").map(&:value)
      [Digest::SHA256.hexdigest(xml), fills]
    end

    it "preserves the SVG and categorical palette" do
      expect(rendering).to eq(
        ["244e072b16e946dde4cfa7f00a1806610f32f5a646e0f0d4a95e62fa50f403af",
         palette],
      )
    end
  end

  context "with the dark theme" do
    let(:rendering) do
      document = REXML::Document.new(Sirena.render(source, theme: :dark))
      circle = REXML::XPath.first(document, "//circle/@stroke")
      paths = REXML::XPath.match(document, "//path")
      texts = REXML::XPath.match(document, "//text/@fill")
      [circle.value, paths.map { |path| path.attributes["stroke"] },
       texts.map(&:value), paths.map { |path| path.attributes["fill"] }]
    end

    it "uses semantic roles without changing the categorical palette" do
      expect(rendering).to eq(
        ["#d4d4d4", %w[#858585 #858585], Array.new(5, "#d4d4d4"), palette],
      )
    end
  end

  context "with no scalar theme colors" do
    let(:rendering) do
      theme = Sirena::Theme.new(name: "partial")
      document = REXML::Document.new(Sirena.render(source, theme: theme))
      circle = REXML::XPath.first(document, "//circle")
      paths = REXML::XPath.match(document, "//path")
      texts = REXML::XPath.match(document, "//text")
      [circle.attributes["stroke"],
       paths.map { |path| path.attributes["stroke"] },
       texts.map { |text| text.attributes["fill"] },
       paths.map { |path| path.attributes["fill"] }]
    end

    it "leaves roles unpainted and completes the categorical palette" do
      expect(rendering).to eq([nil, [nil, nil], Array.new(5), palette])
    end
  end
end
