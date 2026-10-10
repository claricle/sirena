# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

module PlantUmlCaptionHelpers
  def wrap(*lines)
    "@startuml\n#{lines.join("\n")}\n@enduml\n"
  end

  def parse_plantuml(source)
    Sirena::Notation::PlantUML::Parser.new.parse(source)
  end

  def refusal_of(source)
    parse_plantuml(source)
    nil
  rescue Sirena::Notation::PlantUML::UnsupportedConstructError => e
    e
  end

  def drawn(*lines)
    REXML::Document.new(Sirena.render(wrap(*lines), notation: :plantuml))
  end

  def panel(svg, kind)
    REXML::XPath.first(svg, "//g[@id='caption-#{kind}']")
  end

  def number(element, name)
    element.attributes[name].to_f
  end

  def style_block(*properties)
    ["<style>", "document {", *properties, "}", "</style>", "class A"]
  end
end

RSpec.describe Sirena::Notation::PlantUML do
  include PlantUmlCaptionHelpers

  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(described_class) }

  describe "reading a caption line" do
    {
      "title My diagram" => [:title, "My diagram"],
      "HEADER top" => [:header, "top"],
      "footer page 2, draft!" => [:footer, "page 2, draft!"],
      "caption Figure 1" => [:caption, "Figure 1"],
      "legend legend" => [:legend, "legend"],
    }.each do |line, (kind, text)|
      it "reads #{line.inspect} as a #{kind}" do
        caption = described_class::Caption.read(line)

        expect([caption.kind, caption.text]).to eq([kind, text])
      end
    end

    [
      "title", "title **bold**", 'title say "hi"', "title a\\nb", "title <b>x</b>",
      "title --> T", "legend right", "legend Center", "title a/b", "titles x",
      "header <-- T", "title a *b*"
    ].each do |line|
      it "leaves #{line.inspect} to the refusal rules" do
        expect(described_class::Caption.read(line)).to be_nil
      end
    end

    it "keeps the later of two titles, as PlantUML draws" do
      diagram = parse_plantuml(wrap("title a", "title b", "class A"))

      expect(diagram.captions.map(&:text)).to eq(["b"])
    end
  end

  describe "reading a style block" do
    it "reads the canvas and the properties of each caption kind" do
      diagram = parse_plantuml(wrap(*style_block(
        "BackGroundColor orange", "footer {", "fontsize 15", "FontColor red",
        "BackGroundColor #00f", "}"
      )))

      expect([diagram.style.background, diagram.style.rule(:footer)])
        .to eq(["#FFA500", { size: 15, colour: "#FF0000",
                             background: "#0000FF" }])
    end

    {
      "FontName Arial" => "style property fontname",
      "Border {" => "style selector Border",
      "FontSize" => "style rule form",
      "BackGroundColor teal" => "style colour",
    }.each do |line, construct|
      it "refuses #{line.inspect} inside the document by name" do
        expect(refusal_of(wrap("<style>", "document {", line)))
          .to have_attributes(construct: construct, line: 4)
      end
    end

    it "refuses a property of the document other than its background" do
      source = wrap("<style>", "document {", "FontColor red", "}", "</style>",
                    "class A")

      expect(refusal_of(source).construct).to eq("style property fontcolor")
    end

    it "refuses a caption selector outside the document" do
      source = wrap("<style>", "footer {", "}", "</style>", "class A")

      expect(refusal_of(source).construct).to eq("style selector footer")
    end

    it "does not take a line starting with an apostrophe for a comment" do
      source = wrap("<style>", "document {", "'FontColor red", "}", "</style>",
                    "class A")

      expect(refusal_of(source).construct).to eq("style rule form")
    end

    it "refuses a font size that is not a whole number" do
      source = wrap(*style_block("title {", "FontSize 1.5", "}"))

      expect(refusal_of(source).construct).to eq("style font size")
    end

    it "refuses a selector nested inside a caption" do
      source = wrap(*style_block("title {", "footer {", "}", "}"))

      expect(refusal_of(source).construct).to eq("style selector footer")
    end

    it "refuses a second style block" do
      source = wrap(*style_block, "<style>", "</style>")

      expect(refusal_of(source).construct).to eq("second style block")
    end

    it "refuses a block that is never closed" do
      expect { parse_plantuml(wrap("<style>", "document {", "}")) }
        .to raise_error(Sirena::Parser::ParseError, /line 2 .*never closed/)
    end

    it "refuses a close tag with a selector still open" do
      expect { parse_plantuml(wrap("<style>", "document {", "</style>")) }
        .to raise_error(Sirena::Parser::ParseError, /document still open/)
    end
  end

  describe "drawing captions" do
    let(:svg) do
      drawn("title T", "header H", "footer F", "caption C", "legend L",
            "class Bob", "class Sally", "Sally --> Bob")
    end
    let(:rows) do
      %w[header title legend caption footer].to_h do |kind|
        [kind, number(panel(svg, kind).elements["text"], "y")]
      end
    end

    it "stacks them header, title, legend, caption, footer" do
      expect(rows.values).to eq(rows.values.sort)
    end

    it "puts the content between the title and the legend" do
      content = REXML::XPath.first(svg, "//g[@id='class-Bob']/rect")
      shift = svg.root.elements["g"].attributes["transform"][/, ([\d.]+)\)/, 1]

      expect(number(content, "y") + shift.to_f)
        .to be_between(rows["title"], rows["legend"])
    end

    it "keeps the whole canvas around every panel" do
      rects = REXML::XPath.match(svg, "//g[starts-with(@id,'caption-')]/rect")

      expect(rects.map { |r| number(r, "y") + number(r, "height") }.max)
        .to be < number(svg.root, "height")
    end

    it "puts the title in the middle" do
      expect(number(panel(svg, "title").elements["text"], "x"))
        .to eq(number(svg.root, "width") / 2)
    end

    it "puts the header against the right edge" do
      header = panel(svg, "header").elements["rect"] ||
               panel(svg, "header").elements["text"]

      expect(number(header, "x")).to be > number(svg.root, "width") / 2
    end

    it "draws the legend as a bordered box" do
      rect = panel(svg, "legend").elements["rect"].attributes

      expect([rect["stroke"], rect["fill"]]).to eq(%w[#000000 #DDDDDD])
    end

    it "draws the title as bare text" do
      expect(panel(svg, "title").elements["rect"]).to be_nil
    end

    it "grays the header and footer and bolds the title" do
      text = ->(kind) { panel(svg, kind).elements["text"].attributes }

      expect([text.("header")["fill"], text.("footer")["fill"],
              text.("title")["font-weight"], text.("caption")["font-weight"]])
        .to eq(["#888888", "#888888", "bold", nil])
    end

    it "moves the diagram down as one group" do
      expect(svg.root.elements["g"].attributes["transform"])
        .to match(/translate\(\d.* [1-9]/)
    end

    it "leaves the diagram alone with no captions" do
      expect(REXML::XPath.match(drawn("class A"), "//g[@transform]")).to be_empty
    end
  end

  describe "drawing a style" do
    let(:styled) do
      drawn("title T", *style_block(
        "BackGroundColor orange", "title {", "BackGroundColor yellow",
        "FontColor red", "FontSize 20", "}"
      ))
    end

    it "fills the canvas" do
      expect(styled.root.elements["rect"].attributes["fill"]).to eq("#FFA500")
    end

    it "fills a caption's box" do
      expect(panel(styled, "title").elements["rect"].attributes["fill"])
        .to eq("#FFFF00")
    end

    it "sets a caption's font colour and size" do
      text = panel(styled, "title").elements["text"].attributes

      expect([text["fill"], text["font-size"]]).to eq(["#FF0000", "20.0"])
    end

    it "draws a styled legend with its fill changed and its border kept" do
      svg = drawn("legend L", *style_block("legend {", "BackGroundColor green",
                                           "}"))
      rect = panel(svg, "legend").elements["rect"].attributes

      expect([rect["fill"], rect["stroke"]]).to eq(["#008000", "#000000"])
    end

    it "sets the font size a style gives" do
      small = drawn("title T", "class A")
      large = drawn("title T", *style_block("title {", "BackGroundColor red",
                                            "FontSize 40", "}"))
      size = ->(svg) { number(panel(svg, "title").elements["text"], "font-size") }

      expect(size.(large)).to be > size.(small)
    end
  end
end
