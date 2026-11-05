# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

RSpec.describe Sirena::Notation::PlantUML::Further do
  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  def render(source)
    svg = Sirena::Engine.new.render(source, notation: :plantuml)
    REXML::Document.new(svg)
  end

  def elements(doc, name)
    REXML::XPath.match(doc, "//#{name}")
  end

  def path_data(doc)
    elements(doc, "path").map { |path| path.attributes["d"] }
  end

  describe "clock edges" do
    let(:clock) do
      render("@startuml\nclock \"K\" as K with period 50\n" \
             "@0\n@100\n@enduml\n")
    end
    let(:points) do
      path_data(clock).first.scan(/([ML]) ([\d.]+) ([\d.]+)/)
        .map { |_, x, y| [x.to_f, y.to_f] }
    end

    it "opens with a stroke up from low when the clock rises at the start" do
      expect([points[0][0] == points[2][0], points[0][1] > points[2][1]])
        .to eq([true, true])
    end

    it "closes with the edge that falls exactly on the finish" do
      xs = points.map(&:first)
      expect(xs.count(xs.max)).to be >= 2
    end

    it "keeps a clock that starts at its offset low until the first rise" do
      doc = render("@startuml\nclock \"K\" as K with period 50 pulse 15 " \
                   "offset 10\n@0\n@100\n@enduml\n")
      first = path_data(doc).first.scan(/[\d.]+/).map(&:to_f)
      expect(first[1]).to eq(first[3])
    end
  end

  describe "message arrows" do
    let(:doc) do
      render("@startuml\nrobust \"A\" as A\nconcise \"B\" as B\n@0\n" \
             "A is x\nB is y\n@100\nB -> A : URL\n@enduml\n")
    end

    it "sets the label in 14 point serif" do
      label = elements(doc, "text").find { |t| t.text == "URL" }
      expect(%w[font-family font-size].map { |a| label.attributes[a] })
        .to eq(%w[Serif 14])
    end

    it "draws the arrow and its head at one and a half pixels" do
      blue = elements(doc, "*").select do |e|
        e.attributes["stroke"] == "#00008B"
      end
      expect(blue.map { |e| e.attributes["stroke-width"] }.uniq)
        .to eq(["1.5"])
    end
  end

  describe "railroad diagrams" do
    let(:doc) do
      render("@startebnf\nn = \"1\", [{\"0\"}-] ;\n@endebnf\n")
    end

    it "draws the loop back above the box it repeats" do
      boxes = elements(doc, "rect")
      loop_path = path_data(doc).max_by(&:length)
      ys = loop_path.scan(/[ML] [\d.]+ ([\d.]+)/).flatten.map(&:to_f)
      repeated = boxes.last.attributes["y"].to_f
      expect(ys.min).to be < repeated
    end

    it "points the loop arrow back against the rail" do
      arrow = elements(doc, "polygon").first.attributes["points"]
      xs = arrow.split.map { |pt| pt.split(",").first.to_f }
      expect(xs.first).to be < xs.last
    end

    it "draws rails thick and boxes white and thin" do
      box = elements(doc, "rect").first.attributes
      expect([elements(doc, "line").first.attributes["stroke-width"],
              box["fill"], box["stroke-width"]])
        .to eq(["1.5", "#FFFFFF", "0.5"])
    end
  end
end
