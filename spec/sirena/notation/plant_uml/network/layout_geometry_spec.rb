# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"

# Sizes and offsets measured on PlantUML 1.2026.6 (corpus 13-1-2, 13-4-1).
RSpec.describe Sirena::Notation::PlantUML::Network::Layout,
               :aggregate_failures do
  include_context "with an isolated notation registry"

  before do
    Sirena::Notation.register(Sirena::Notation::PlantUML) unless
      Sirena::Notation.ids.include?(Sirena::Notation::PlantUML.id)
  end

  let(:two_networks) do
    <<~PUML
      nwdiag {
        network front {
          address = "10.0.0.0/24"
          web01 [address = ".1, .2", shape = "node"]
        }
        network back {
          db01 [address = ".101", shape = database]
        }
      }
    PUML
  end
  let(:joined) do
    "nwdiag {\n network n {\n a\n }\n network m {\n b\n a\n }\n}"
  end
  let(:single) { parse("nwdiag {\n network n {\n web02\n }\n}") }
  let(:grouped) do
    parse("nwdiag {\n network n {\n group g {\n web01\n web02\n }\n }\n}")
  end

  def parse(body)
    REXML::Document.new(Sirena.render("@startuml\n#{body}\n@enduml",
                                      notation: :plantuml))
  end

  def rects(doc)
    REXML::XPath.match(doc, "//rect").map do |r|
      r.attributes.each_attribute.to_h { |a| [a.name, a.value] }
    end
  end

  def papers(doc)
    rects(doc).select { |r| r["fill"] == "#F1F1F1" }.sort_by { |r| r["x"].to_f }
  end

  def bars(doc)
    rects(doc).select { |r| r["height"].to_i == 5 }
  end

  def link_xs(doc)
    REXML::XPath.match(doc, "//line").select do |l|
      l.attributes["x1"] == l.attributes["x2"]
    end.map { |l| l.attributes["x1"].to_f }
  end

  def name_width(name)
    Sirena::Notation::PlantUML::Drawing::Face.width(name, size: 12)
  end

  def centre(rect)
    rect["x"].to_f + (rect["width"].to_f / 2)
  end

  it "stacks 5 pixel bars with their names right-aligned 5 before them" do
    doc = parse(two_networks)
    names = REXML::XPath.match(doc, "//text[@text-anchor='end']")

    expect(bars(doc).size).to eq(2)
    expect(names.map { |t| t.attributes["x"].to_f }.uniq)
      .to eq([bars(doc).first["x"].to_f - 5])
  end

  it "makes a box 20 wider than its name and 34.13 high" do
    box = papers(single).first

    expect(box["height"].to_f).to eq(34.1328)
    expect(box["width"].to_f)
      .to be_within(0.001).of(name_width("web02") + 20)
  end

  it "keeps a lone node's bar at least 70 wide, boxes inset 15" do
    narrow = parse("nwdiag {\n network n {\n a\n }\n}")
    bar = bars(narrow).first

    expect(bar["width"].to_f).to eq(70.0)
    expect(papers(narrow).first["x"].to_f - bar["x"].to_f).to eq(15.0)
  end

  it "draws a cube's front face with three further edges" do
    polygon = REXML::XPath.first(parse(two_networks), "//polygon")

    expect(polygon.attributes["points"].split.size).to eq(6)
    expect(polygon.attributes["stroke-width"]).to eq("0.5")
  end

  it "draws a database as a body and a lid's front edge, no ellipse" do
    doc = parse(two_networks)
    curved = REXML::XPath.match(doc, "//path")
      .select { |p| p.attributes["d"].include?("Q") }

    expect(REXML::XPath.match(doc, "//ellipse")).to be_empty
    expect(curved.size).to be >= 2
  end

  it "hangs a joining node's line 2 left of its centre, others 2 right" do
    boxes = papers(parse(joined))
    xs = link_xs(parse(joined))

    expect(xs).to include(centre(boxes[0]) + 2, centre(boxes[1]) - 2)
  end

  it "ends the canvas 47.75 under the last row" do
    box = papers(single).first
    bottom = box["y"].to_f + box["height"].to_f

    expect(single.root.attributes["height"].to_f)
      .to eq((bottom + 47.75).ceil.to_f)
  end

  it "shades a group 5 pixels round its members in the JAR's grey" do
    shade = rects(grouped).find { |r| r["fill"] == "#E7E7E7" }

    expect(shade["x"].to_f).to eq(papers(grouped).first["x"].to_f - 5)
    expect(shade["height"].to_f).to be_within(0.001).of(34.1328 + 10)
  end
end
