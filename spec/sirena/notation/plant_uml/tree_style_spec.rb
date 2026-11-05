# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

# The `<style>` rules of a PlantUML mindmap or work breakdown structure:
# plugin corpus fixture 18-7 verbatim, and the edges of the rule reader.
RSpec.describe Sirena::Notation::PlantUML::Tree do
  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  let(:root) { REXML::Document.new(Sirena.render(source)).root }

  def elements(name)
    REXML::XPath.match(root, "//*[local-name()='#{name}']")
  end

  def box_of(label)
    text = text_of(label)
    point = %w[x y].map { |name| text.attributes[name].to_f }
    elements("rect").find { |rect| holds?(rect, *point) }
  end

  def holds?(rect, x_pos, y_pos)
    left, top, width, height = %w[x y width height].map do |name|
      rect.attributes[name].to_f
    end
    x_pos.between?(left, left + width) && y_pos.between?(top, top + height)
  end

  def attrs(element)
    element.attributes.each_attribute.to_h { |a| [a.expanded_name, a.value] }
  end

  def text_of(label)
    elements("text").find { |item| item.texts.join == label }
  end

  def strokes(width = nil)
    paths = elements("path")
    paths = paths.select { |p| p.attributes["stroke-width"] == width } if width
    paths.map { |path| path.attributes["stroke"] }.tally
  end

  context "with fixture 18-7, a work breakdown with a style block" do
    let(:source) do
      <<~PUML
        @startwbs
        <style>
        wbsDiagram {
          // all lines (meaning connector and borders, there are no other lines in WBS) are black by default
          Linecolor black
          arrow {
            // note that connector are actually "arrow" even if they don't look like as arrow
            LineColor green
          }
          :depth(0) {
            // will target root node
            BackgroundColor White
            RoundCorner 10
            LineColor red
          }
          arrow {
            :depth(2) {
              // Targetting only connector between Mexico-Chihuahua and USA-Texas
              LineColor blue
              LineStyle 4
              LineThickness .5
            }
          }
          node {
            :depth(2) {
              LineStyle 2
              LineThickness 2.5
            }
          }
          boxless {
            // will target boxless node with '_'
            FontColor darkgreen
          }
        }
        </style>
        * World
        ** America
        *** Canada
        *** Mexico
        **** Chihuahua
        *** USA
        **** Texas
        ***< New York
        ** Europe
        ***_ England
        ***_ Germany
        ***_ Spain
        @endwbs
      PUML
    end

    it "draws the root white with a red outline and rounded corners" do
      expect(attrs(box_of("World")))
        .to include("fill" => "#FFFFFF", "stroke" => "#FF0000", "rx" => "5.0")
    end

    it "outlines the other boxes black" do
      expect(box_of("America").attributes["stroke"]).to eq("#000000")
    end

    it "draws the boxes two levels down dotted and thick" do
      expect(%w[Canada Mexico USA].map { |name| attrs(box_of(name)) })
        .to all(include("stroke-width" => "2.5",
                        "stroke-dasharray" => "2,2"))
    end

    it "leaves the boxes of the other levels solid" do
      expect(box_of("Chihuahua").attributes["stroke-dasharray"]).to be_nil
    end

    it "draws the connectors from the root red" do
      expect(strokes["#FF0000"]).to eq(4)
    end

    it "draws the connectors under the third level thin, blue and dashed" do
      blue = elements("path").select { |p| p.attributes["stroke"] == "#0000FF" }
      expect(blue.map do |p|
        attrs(p).values_at("stroke-width", "stroke-dasharray")
      end)
        .to all(eq(["0.5", "4,4"]))
    end

    it "draws every other connector green" do
      expect(strokes["#008000"]).to eq(9)
    end

    it "sets the boxless nodes in dark green and draws no box for them" do
      expect([text_of("England").attributes["fill"], box_of("England")])
        .to eq(["#006400", nil])
    end

    it "keeps the text of a boxed node black" do
      expect(text_of("America").attributes["fill"]).to eq("#000000")
    end
  end

  context "with a mindmap whose style names its own diagram" do
    let(:source) do
      <<~PUML
        @startmindmap
        <style>
        mindmapDiagram {
          node, arrow { LineColor red }
          .big { BackgroundColor pink }
        }
        </style>
        * Root
        ** Leaf
        @endmindmap
      PUML
    end

    it "outlines the boxes and draws the connectors in the rule's colour" do
      expect([box_of("Leaf").attributes["stroke"], strokes.keys])
        .to eq(["#FF0000", ["#FF0000"]])
    end
  end

  context "with a style block with a class, an unknown selector and values" do
    let(:source) do
      <<~PUML
        @startwbs
        <style>
        wbsDiagram {
          leafNode { LineColor blue }
          node { LineThickness thick
                 LineStyle 0
                 FontSize 9
                 LineColor nonsense }
          node { :depth(1) { BackgroundColor #ABC } }
        }
        </style>
        * Root
        ** Child
        @endwbs
      PUML
    end

    it "ignores a selector it does not know" do
      expect(box_of("Child").attributes["stroke"]).to eq("#181818")
    end

    it "ignores a value that is no number, dash or colour" do
      expect(attrs(box_of("Child")).values_at("stroke-width",
                                              "stroke-dasharray"))
        .to eq(["1.5", nil])
    end

    it "fills a box from a short hex colour" do
      expect(box_of("Child").attributes["fill"]).to eq("#AABBCC")
    end
  end

  describe Sirena::Notation::PlantUML::Tree::Rules do
    it "reports no rule for an empty block" do
      expect(described_class.parse("wbsDiagram {\n}\n").any?).to be(false)
    end

    it "reads the rules of several blocks" do
      rules = described_class.parse("node { LineColor red }")
      rules.add("node { :depth(1) { LineColor blue } }")
      expect([rules.node(0)[:stroke], rules.node(1)[:stroke]])
        .to eq(["#FF0000", "#0000FF"])
    end

    it "lets a deeper rule win over a later shallower one" do
      rules = described_class.parse(
        "node { :depth(0) { LineColor red } }\nnode { LineColor blue }",
      )
      expect(rules.node(0)[:stroke]).to eq("#FF0000")
    end

    it "applies a rule written outside any wrapper" do
      expect(described_class.parse("arrow { LineThickness 3 }").arrow(5))
        .to eq(stroke_width: 3.0)
    end
  end

  describe Sirena::Notation::PlantUML::Tree::Layout do
    it "returns itself when the source styles nothing" do
      rules = Sirena::Notation::PlantUML::Tree::Rules.new
      expect(Sirena::Notation::PlantUML::Tree::WbsLayout.styled(rules))
        .to be(Sirena::Notation::PlantUML::Tree::WbsLayout)
    end
  end
end
