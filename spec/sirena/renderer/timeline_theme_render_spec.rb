# frozen_string_literal: true

require "digest"
require "rexml/document"
require "spec_helper"

RSpec.describe Sirena::Renderer::Timeline, "#render" do
  let(:source) do
    "timeline\n title Roadmap\n section Release\n " \
      "2020 : Alpha\n 2021 : Beta\n"
  end
  let(:scene) do
    diagram = Sirena::Parser::Timeline.new.parse(source)
    Sirena::Layout::Timeline.new.call(diagram)
  end

  context "with the default theme" do
    subject(:default_svg) { described_class.new.render(scene).to_xml }

    let(:edge_strokes) do
      document = REXML::Document.new(default_svg)
      REXML::XPath.match(document, "//g[@class='lineWrapper']").map do |group|
        group.elements["path"].attributes["stroke"]
      end
    end
    let(:title_fill) do
      document = REXML::Document.new(default_svg)
      REXML::XPath.first(document, "//text[@font-weight='bold']")
        .attributes["fill"]
    end
    let(:line_shapes) do
      document = REXML::Document.new(default_svg)
      line_groups = REXML::XPath.match(document, "//g[@class='lineWrapper']")
      line_groups.map do |group|
        [group.elements.to_a.map(&:name),
         group.elements["path"].attributes["stroke-dasharray"]]
      end
    end

    it "uses the default theme for edges and the title" do
      digest = Digest::SHA256.hexdigest(default_svg)
      expected_digest = "1f5b8a7b31d6a87b030cdd081a308b6e" \
                        "c6a710dd0e0754b76746610d0340997c"
      expected = [expected_digest, %w[#000000 #000000 #000000], "#000000"]
      expect([digest, edge_strokes, title_fill]).to eq(expected)
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
    let(:title_fill) do
      document = REXML::Document.new(contrast_svg)
      REXML::XPath.first(document, "//text[@font-weight='bold']")
        .attributes["fill"]
    end

    it "uses the high-contrast edge and title colors" do
      expect([contrast_svg == described_class.new.render(scene).to_xml,
              edge_strokes, title_fill])
        .to eq([false, %w[#ffffff #ffffff #ffffff], "#ffffff"])
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
    let(:title_fill) do
      titled_scene = Sirena::Layout::Timeline.new.call(
        Sirena::Parser::Timeline.new.parse("timeline\n title Empty\n"),
      )
      document = REXML::Document.new(
        described_class.new(theme: Sirena::Theme.new(name: "partial"))
          .render(titled_scene).to_xml,
      )
      REXML::XPath.first(document, "//text[@font-weight='bold']")
        .attributes["fill"]
    end

    it "leaves missing edge and title roles unpainted" do
      expect([edge_strokes, title_fill]).to eq([[nil], nil])
    end
  end
end
