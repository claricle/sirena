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

  describe "message arrows measured on the JAR" do
    let(:doc) do
      render("@startuml\nrobust \"Web Browser\" as WB\n" \
             "concise \"Web User\" as WU\n@0\nWU is Idle\nWB is Idle\n" \
             "@100\nWU -> WB : URL\nWU is Waiting\n@200\nWB is Proc.\n" \
             "@300\nWU -> WB@350 : URL2\nWB is Waiting\n@enduml\n")
    end
    let(:arrows) do
      elements(doc, "line").select { |e| e.attributes["stroke"] == "#00008B" }
    end

    let(:falling) do
      render("@startuml\nrobust \"B\" as B\nconcise \"W\" as W\n@0\n" \
             "W is Idle\nB is Idle\n@100\nB -> W : A\n@enduml\n")
    end

    def tip_y(diagram)
      line = elements(diagram, "line").find do |e|
        e.attributes["stroke"] == "#00008B"
      end
      line.attributes["y2"].to_f
    end

    def label_x(text)
      elements(doc, "text").find { |t| t.text == text }.attributes["x"].to_f
    end

    it "starts a message from the point of a hexagon where a state changes" do
      expect(arrows.first.attributes["y1"].to_f).to be_within(0.01).of(139.98)
    end

    it "starts a message from the top edge of a hexagon between changes" do
      expect(arrows.last.attributes["y1"].to_f).to be_within(0.01).of(127.98)
    end

    it "sets the label of a vertical arrow at its tip" do
      tip_x = arrows.first.attributes["x2"].to_f
      expect(label_x("URL")).to be_within(0.01).of(tip_x)
    end

    it "pulls the label of a slanting arrow back along the arrow" do
      slant = %w[x1 y1 x2 y2].to_h { |k| [k, arrows.last.attributes[k].to_f] }
      dx = slant["x2"] - slant["x1"]
      unit_x = dx / Math.hypot(dx, slant["y2"] - slant["y1"])
      expect(label_x("URL2"))
        .to be_within(0.01).of(slant["x2"] - (7.518 * unit_x))
    end

    it "sets the label of a falling arrow above its tip" do
      text = elements(falling, "text").find { |t| t.text == "A" }
      expect(text.attributes["y"].to_f).to be < tip_y(falling)
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

  describe "railroad text and rails" do
    let(:doc) { render("@startebnf\nn = \"1\", [{\"0\"}-] ;\n@endebnf\n") }

    it "sets box and title text in 14 point" do
      sizes = elements(doc, "text").map { |t| t.attributes["font-size"] }
      expect(sizes.uniq).to eq(["14"])
    end

    it "sizes a box to its text and ten points" do
      box = elements(doc, "rect").first.attributes["width"].to_f
      expect(box).to be_within(0.5).of(
        Sirena::TextMeasurement.measure("1", font_size: 14)[:width] + 10,
      )
    end

    it "marks the direction of the bypass rail and of the end rail" do
      heads = elements(doc, "polygon").map do |e|
        e.attributes["points"].split.map { |pt| pt.split(",").first.to_f }
      end
      pointing_right = heads.select { |xs| xs[1] > xs[0] && xs[1] > xs[2] }
      expect(pointing_right.size).to eq(2)
    end
  end
end
