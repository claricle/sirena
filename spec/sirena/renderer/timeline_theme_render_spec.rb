# frozen_string_literal: true

require "digest"
require "rexml/document"
require "spec_helper"

RSpec.describe Sirena::Renderer::Timeline, "#render" do
  let(:source) do
    "timeline\n section Release\n 2020 : Alpha\n 2021 : Beta\n"
  end
  let(:scene) do
    diagram = Sirena::Parser::Timeline.new.parse(source)
    Sirena::Layout::Timeline.new.call(diagram)
  end

  context "with the default theme" do
    subject(:default_svg) { described_class.new.render(scene).to_xml }

    let(:line_groups) do
      document = REXML::Document.new(default_svg)
      REXML::XPath.match(document, "//g[@class='lineWrapper']")
    end
    let(:edge_strokes) do
      line_groups.map { |group| group.elements["path"].attributes["stroke"] }
    end
    let(:line_shapes) do
      line_groups.map do |group|
        [group.elements.to_a.map(&:name),
         group.elements["path"].attributes["stroke-dasharray"]]
      end
    end

    it "preserves output and black edge strokes" do
      digest = Digest::SHA256.hexdigest(default_svg)
      expected_digest = "8d20551448fd29e319ae3386f9aac76b2" \
                        "031ace778880adec91d2cb1d4750d3b"
      expected = [expected_digest, %w[#000000 #000000 #000000]]
      expect([digest, edge_strokes]).to eq(expected)
    end

    it "keeps dashed connector arrowheads and the solid axis arrowhead" do
      expected = [[%w[path polygon], "5,5"],
                  [%w[path polygon], "5,5"], [%w[path polygon], nil]]
      expect(line_shapes).to eq(expected)
    end
  end

  context "with the high-contrast theme" do
    subject(:contrast_svg) do
      theme = Sirena::Theme::Registry.get(:high_contrast)
      described_class.new(theme: theme).render(scene).to_xml
    end

    let(:edge_strokes) do
      document = REXML::Document.new(contrast_svg)
      REXML::XPath.match(document, "//g[@class='lineWrapper']/path")
        .map { |path| path.attributes["stroke"] }
    end

    it "uses the high-contrast edge stroke" do
      expect([contrast_svg == described_class.new.render(scene).to_xml,
              edge_strokes]).to eq([false, %w[#ffffff #ffffff #ffffff]])
    end
  end

  context "with no theme colors" do
    subject(:partial_svg) do
      theme = Sirena::Theme.new(name: "partial")
      diagram = Sirena::Parser::Timeline.new.parse("timeline\n")
      empty_scene = Sirena::Layout::Timeline.new.call(diagram)
      described_class.new(theme: theme).render(empty_scene).to_xml
    end

    let(:edge_strokes) do
      document = REXML::Document.new(partial_svg)
      REXML::XPath.match(document, "//g[@class='lineWrapper']/path")
        .map { |path| path.attributes["stroke"] }
    end

    it "falls back to black" do
      expect(edge_strokes).to eq(["#000000"])
    end
  end
end
