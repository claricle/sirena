# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"

RSpec.describe Sirena::Notation::PlantUML::Activity::Metrics do
  include_context "with an isolated notation registry"

  before do
    Sirena::Notation.send(:entries).delete(:plantuml)
    Sirena::Notation.register(Sirena::Notation::PlantUML)
  end

  let(:flow) do
    ["start", ":a long action label;", "-> edge label;", "if (ok?) then (yes)",
     ":go;", "note right: a note", "else (no)", ":stop it;", "endif",
     "partition Part {", ":in part;", "}", "-> out;", "stop"]
  end

  def root_for(*lines)
    xml = Sirena::Engine.new.render("@startuml\n#{lines.join("\n")}\n@enduml\n")
    REXML::Document.new(xml).root
  end

  def texts(root)
    REXML::XPath.match(root, "//*[local-name()='text']")
  end

  def size_of(root, content)
    texts(root).find { |t| t.text == content }.attributes["font-size"]
  end

  def rects(root)
    REXML::XPath.match(root, "//*[local-name()='rect']")
  end

  def number(element, name)
    element.attributes[name].to_f
  end

  def spans?(rect, text)
    number(rect, "x") < number(text, "x") &&
      number(rect, "x") + number(rect, "width") > number(text, "x") &&
      number(rect, "y") < number(text, "y") &&
      number(rect, "y") + number(rect, "height") > number(text, "y")
  end

  def box_of(root, label)
    text = texts(root).find { |t| t.text == label }
    rects(root).find { |r| r.attributes["fill"] != "none" && spans?(r, text) }
  end

  def width_of(root, label)
    number(box_of(root, label), "width")
  end

  def height_of(root, label)
    number(box_of(root, label), "height")
  end

  describe "a <style> sheet" do
    let(:sheet) do
      ["<style>", "activityDiagram {", "FontSize 20", "diamond {",
       "FontSize 18", "}", "arrow {", "FontSize 9", "}", "note {",
       "FontSize 16", "}", "partition {", "FontSize 22", "}", "}", "</style>"]
    end
    let(:root) { root_for(*sheet, *flow) }

    it "sizes each role from its own rule" do
      sizes = ["a long action label", "ok?", "edge label", "a note", "Part"]
        .map { |label| size_of(root, label) }

      expect(sizes).to eq(%w[20 18 9 16 22])
    end

    it "gives every role the activityDiagram size when it has no rule" do
      root = root_for("<style>", "activityDiagram {", "FontSize 20", "}",
                      "</style>", *flow)

      expect(["a long action label", "ok?", "edge label", "a note", "Part"]
        .map { |label| size_of(root, label) }.uniq).to eq(["20"])
    end

    it "grows the action box to fit its larger text" do
      plain = root_for(*flow)

      expect(width_of(root, "a long action label"))
        .to be > width_of(plain, "a long action label") * 1.5
    end

    it "grows the box taller with the font" do
      plain = root_for(*flow)

      expect(height_of(root, "a long action label"))
        .to be > height_of(plain, "a long action label")
    end

    it "keeps every action label inside its box" do
      text = texts(root).find { |t| t.text == "a long action label" }
      width = width_of(root, "a long action label")
      measured = Sirena::TextMeasurement
        .measure(text.text, font_size: 20)[:width]

      expect(measured).to be < width
    end

    it "keeps the partition title clear of the arrow entering the frame" do
      frame = rects(root).find { |r| r.attributes["fill"] == "none" }
      title = texts(root).find { |t| t.text == "Part" }
      centre = frame.attributes["x"].to_f + (frame.attributes["width"].to_f / 2)

      expect(title.attributes["x"].to_f).to be < centre
    end
  end

  describe "skinparam" do
    it "applies activityFontSize to actions only" do
      root = root_for("skinparam activityFontSize 20", *flow)

      expect([size_of(root, "a long action label"), size_of(root, "ok?")])
        .to eq(%w[20 12])
    end

    it "applies the per-role keys" do
      root = root_for("skinparam activityDiamondFontSize 18",
                      "skinparam ArrowFontSize 9", "skinparam noteFontSize 16",
                      "skinparam partitionFontSize 22", *flow)

      expect(["ok?", "edge label", "a note", "Part"]
        .map { |label| size_of(root, label) }).to eq(%w[18 9 16 22])
    end

    it "applies defaultFontSize to every role" do
      root = root_for("skinparam defaultFontSize 20", *flow)

      expect(["a long action label", "ok?", "edge label", "a note", "Part"]
        .map { |label| size_of(root, label) }.uniq).to eq(["20"])
    end

    it "lets a <style> rule win over skinparam" do
      root = root_for("skinparam activityFontSize 20", "<style>",
                      "activityDiagram {", "FontSize 16", "}", "</style>",
                      *flow)

      expect(size_of(root, "a long action label")).to eq("16")
    end
  end

  it "keeps the default size when the source sets none" do
    root = root_for(*flow)

    expect(texts(root).map { |t| t.attributes["font-size"] }.uniq)
      .to eq(["12"])
  end

  describe "the label of an edge leaving a partition" do
    it "hangs below the frame, not over it" do
      root = root_for(*flow)
      frame = rects(root).find { |r| r.attributes["fill"] == "none" }
      label = texts(root).find { |t| t.text == "out" }
      bottom = frame.attributes["y"].to_f + frame.attributes["height"].to_f

      expect(label.attributes["y"].to_f - 12).to be >= bottom - 1
    end
  end
end
