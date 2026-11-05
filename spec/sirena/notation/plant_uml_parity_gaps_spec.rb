# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

RSpec.describe Sirena::Notation::PlantUML do
  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(described_class) }

  def render(body)
    Sirena.render("@startuml\n#{body}\n@enduml\n", notation: :plantuml)
  end

  def nodes(svg, xpath)
    REXML::XPath.match(REXML::Document.new(svg), xpath)
  end

  def box_span(svg)
    box = nodes(svg, "//g[@id='class-A']/rect").first.attributes
    top = box["y"].to_f
    height = box["height"].to_f
    [top, top + height]
  end

  def member_row_ys(svg)
    nodes(svg, "//g[@id='class-A']/text").drop(1)
      .map { |row| row.attributes["y"].to_f }
  end

  def member_ys(svg)
    nodes(svg, "//text[@text-anchor='start']")
      .map { |t| t.attributes["y"].to_f }
  end

  describe "class member rows" do
    let(:svg) { render("class A {\n+field : int\n--\n+method()\n}") }
    let(:box) { nodes(svg, "//g[@id='class-A']/rect").first }

    it "keeps every member baseline inside the class box" do
      top = box.attributes["y"].to_f

      rows = nodes(svg, "//g[@id='class-A']/text").drop(1)

      expect(rows.map { |row| row.attributes["y"].to_f }).to all(
        be_between(top, top + box.attributes["height"].to_f),
      )
    end

    it "draws the field/method rule between the two member rows" do
      rule = nodes(svg, "//g[@id='class-A']/line")
        .map { |l| l.attributes["y1"].to_f }.max

      expect(rule).to be_between(*member_ys(svg).minmax)
    end
  end

  describe "node-graph edge labels" do
    let(:svg) do
      render("node A\nnode B\nA --> B : first\nA --> B : second\n" \
             "B --> A : third")
    end
    let(:gaps) do
      ys = nodes(svg, "//text").select { |t| t.text.to_s.match?(/\A[fst]/) }
        .map { |t| t.attributes["y"].to_f }.sort
      ys.each_cons(2).map { |a, b| b - a }
    end

    it "places labels of parallel edges at least a line apart" do
      expect(gaps.size).to eq(2).and(satisfy { gaps.min >= 12 })
    end
  end

  describe "bracketed relation style" do
    let(:svg) { render("class A\nclass B\nA -[#red,thickness=3]-> B") }
    let(:line) { nodes(svg, "//path[@stroke='red']").first }

    it "carries the colour into the class SVG" do
      expect(line).not_to be_nil
    end

    it "carries the thickness into the class SVG" do
      expect(line.attributes["stroke-width"].to_f).to eq(3.0)
    end

    it "carries a dotted style as a dash array" do
      expect(render("class A\nclass B\nA -[dotted]-> B"))
        .to match(/stroke-dasharray="[\d, ]+"/)
    end
  end

  describe "deployment container shapes" do
    let(:svg) { render("node N\ndatabase D\ncloud C\nfolder F\nN --> D") }

    it "draws the node cube outline as polygons" do
      expect(nodes(svg, "//polygon").size).to be >= 3
    end

    it "draws the cloud as curves" do
      expect(nodes(svg, "//path[contains(@d,'Q')]")).not_to be_empty
    end

    it "draws the database cylinder as arcs" do
      expect(nodes(svg, "//path[contains(@d,' A')]")).not_to be_empty
    end
  end

  describe "creole markup" do
    let(:svg) { render("A -> B : a //italic// and --gone-- and **bold**") }
    let(:spans) { nodes(svg, "//text/tspan") }

    it "leaves no literal markers" do
      expect(svg).not_to match(%r{//italic//|\*\*bold\*\*|--gone--})
    end

    it "renders emphasis as styled tspans" do
      expect(spans.map { |s| s.attributes["font-style"] }).to include("italic")
    end

    it "renders strike-through" do
      expect(spans.map { |s| s.attributes["text-decoration"] })
        .to include("line-through")
    end

    it "preserves the spaces between tspans" do
      expect(nodes(svg, "//text[tspan]").first.attributes["xml:space"])
        .to eq("preserve")
    end
  end

  describe "qualified association box with members" do
    let(:svg) do
      render("class A {\n+f : int\n--\n+m()\n}\nclass B\n" \
             "A \"[key]\" --> \"1\" B")
    end

    it "grows the box to hold its member rows" do
      expect(member_row_ys(svg)).to all(be_between(*box_span(svg)))
    end
  end
end
