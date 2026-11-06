# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"

RSpec.describe Sirena::Notation::PlantUML::QualifierBox do
  def place(outward, endpoint: [100.0, 50.0])
    described_class.place("key", endpoint, outward, 20.0, 14.0)
  end

  def geometry(placed)
    box = placed.box
    [box.x, box.y, box.width, box.height].map { |value| value.round(2) }
  end

  it "hangs below a class edge a link leaves downward, centred on the link" do
    placed = place([0.0, 1.0])

    expect([geometry(placed), placed.clearance.round(2)])
      .to eq([[88.0, 49.5, 24.0, 18.49], 17.99])
  end

  it "stands above a class edge a link leaves upward" do
    expect(geometry(place([0.0, -1.0]))).to eq([88.0, 32.01, 24.0, 18.49])
  end

  it "lies to the right of an edge a link leaves rightward, centred on it" do
    placed = place([1.0, 0.0])

    expect([geometry(placed), placed.clearance.round(2)])
      .to eq([[99.5, 40.76, 24.0, 18.49], 23.5])
  end

  it "lies to the left of an edge a link leaves leftward" do
    expect(geometry(place([-1.0, 0.0]))).to eq([76.5, 40.76, 24.0, 18.49])
  end

  it "writes the text two pixels inside the box, on the reference baseline" do
    text = place([0.0, 1.0]).box.texts.first

    expect([text.content, text.x, text.y.round(2), text.anchor])
      .to eq(["key", 90.0, 64.04, "start"])
  end

  describe "in a class diagram" do
    include_context "with an isolated notation registry"

    before do
      Sirena::Notation.send(:entries).delete(:plantuml)
      Sirena::Notation.register(Sirena::Notation::PlantUML)
    end

    def document(link)
      source = "@startuml\nclass A\nclass B\n#{link}\n@enduml\n"
      REXML::Document.new(Sirena.render(source, notation: :plantuml))
    end

    def relation(link)
      REXML::XPath.first(document(link), "//g[starts-with(@id, 'relation-')]")
    end

    def rects(group)
      REXML::XPath.match(group, "rect")
    end

    def label(group)
      REXML::XPath.first(group, "text[@text-anchor='start']").text
    end

    def path_points(group)
      REXML::XPath.first(group, "path").attributes["d"].split
    end

    it "draws a vertical link's qualifier as a box under its class" do
      group = relation("A [key: string] *-- \"1\" B")
      box = rects(group).first.attributes
      gap = path_points(group)[2].to_f - box["y"].to_f - box["height"].to_f

      expect([label(group), box["height"], gap.round(2)])
        .to eq(["key: string", "18.4883", 0.0])
    end

    it "draws the qualifier written before the second class under that class" do
      group = relation("A *-- [key: string] B")
      box = rects(group).first.attributes

      expect([box["height"].to_f.round(2),
              path_points(group).last.to_f.round(1) <= box["y"].to_f.round(1)])
        .to eq([18.49, true])
    end

    it "leaves a labelled link's qualifier as text" do
      expect(rects(relation("A [key] *-- B : owns"))).to be_empty
    end

    it "leaves a self link's qualifier as text" do
      expect(rects(relation("A [key] --> A"))).to be_empty
    end

    it "leaves a flat link's qualifier as text" do
      group = relation("A -right-> [key] B")

      expect([rects(group), REXML::XPath.first(group, "text").text])
        .to eq([[], "key"])
    end

    it "leaves a bent link's qualifier as text" do
      source = "@startuml\nclass A\nclass B\nclass C\n" \
               "A --> B\nA [key] --> C\n@enduml\n"
      svg = REXML::Document.new(Sirena.render(source, notation: :plantuml))

      expect(REXML::XPath.match(svg, "//g[@id='relation-1']/rect")).to be_empty
    end
  end
end
