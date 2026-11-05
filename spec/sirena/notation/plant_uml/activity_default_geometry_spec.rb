# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"

# Every number is read off the PlantUML JAR 1.2026.6 drawing the same
# unstyled source; the comment on each example names it.
RSpec.describe Sirena::Notation::PlantUML::Activity do
  include_context "with an isolated notation registry"

  before do
    Sirena::Notation.send(:entries).delete(:plantuml)
    Sirena::Notation.register(Sirena::Notation::PlantUML)
  end

  def root_for(*lines)
    xml = Sirena::Engine.new.render("@startuml\n#{lines.join("\n")}\n@enduml\n")
    REXML::Document.new(xml).root
  end

  def polygons(root)
    REXML::XPath.match(root, "//*[local-name()='polygon']").map do |polygon|
      polygon.attributes["points"].split.map { |p| p.split(",").map(&:to_f) }
    end
  end

  def hexagon_in(root)
    polygons(root).find { |points| points.size == 6 }
  end

  def extent(points, axis)
    values = points.map { |point| point[axis] }
    values.max - values.min
  end

  def arial(text, size)
    Sirena::TextMeasurement.measure(text, font_size: size)[:width]
  end

  def trebuchet(text, size)
    Sirena::TextMeasurement.measure_in(:trebuchet, text,
                                       font_size: size)[:width]
  end

  def actions(root)
    REXML::XPath.match(root, "//*[local-name()='rect']")
      .reject { |rect| rect.attributes["fill"] == "none" }
      .sort_by { |rect| rect.attributes["x"].to_f }
  end

  def number(element, name)
    element.attributes[name].to_f
  end

  def wide_branches
    root_for("if (c?) then (y)", ":a very very long left action text;",
             "else (n)", ":another quite long right action text;", "endif")
  end

  def decision(label, *rest)
    root_for("if (#{label}) then (y)", ":Go;", *rest, "endif")
  end

  describe "a decision" do
    let(:hexagon) { hexagon_in(decision("Is it ok?")) }

    # JAR: "Is it ok?" at 11 is 40.86 wide in a 64.86 hexagon
    it "is a hexagon as wide as its text plus 24" do
      expect(extent(hexagon, 0))
        .to be_within(0.01).of(arial("Is it ok?", 11) + 24)
    end

    # JAR: points (56.02,109.13) (96.88,109.13) (108.88,121.13): 12 in
    it "reaches its points 12 beyond the text" do
      expect(hexagon[2][0] - hexagon[1][0]).to eq(12.0)
    end

    # JAR: 109.13 to 133.13
    it "is 24 tall for one line" do
      expect(extent(hexagon, 1)).to eq(24.0)
    end

    # JAR: two lines of 12.955 are 25.91 tall
    it "grows with its lines, never below 24" do
      two = hexagon_in(root_for("if (Line one\\nline two) then (y)", ":Go;",
                                "endif"))

      expect(extent(two, 1)).to be_within(0.01).of(2 * 1.1777 * 11)
    end

    # JAR: "c?" at 11 stands in a 48 wide hexagon
    it "is at least 24 plus its two points wide" do
      expect(extent(hexagon_in(decision("c?")), 0)).to eq(48.0)
    end
  end

  # JAR: the merge after an if is a 24 by 24 diamond
  it "draws the merge diamond 24 by 24" do
    merge = polygons(decision("c?")).find do |points|
      points.size == 4 && points.map(&:first).uniq.size == 3
    end

    expect([extent(merge, 0), extent(merge, 1)]).to eq([24.0, 24.0])
  end

  # JAR: "Hello world" is a 34.13 high box, 20 wider than its text
  it "pads an action 10 on every side" do
    rect = actions(root_for(":Hello world;")).first

    expect([number(rect, "height"), number(rect, "width")])
      .to eq([(1.1777 * 12) + 20, arial("Hello world", 12) + 20])
  end

  # JAR: two wide branches stand 20 apart
  it "keeps 20 between the boxes of two branches" do
    left, right = actions(wide_branches)

    expect(number(right, "x") - number(left, "x") - number(left, "width"))
      .to be_within(0.01).of(20.0)
  end

  describe "the FontName of the source" do
    def style(face, *inner)
      ["<style>", "activityDiagram {", "FontName #{face}", *inner, "}",
       "</style>"]
    end

    def action_width(face)
      number(actions(root_for(*style(face), ":Hello world;")).first, "width")
    end

    it "measures in Trebuchet when it names Trebuchet MS" do
      expect(action_width("Trebuchet MS"))
        .to be_within(0.01).of(trebuchet("Hello world", 12) + 20)
    end

    it "measures in Arial for a face without a table" do
      expect(action_width("Courier"))
        .to be_within(0.01).of(arial("Hello world", 12) + 20)
    end

    it "measures the diamond's own FontName over the diagram's" do
      lines = style("Courier", "diamond {", "FontName Trebuchet MS", "}")
      hexagon = hexagon_in(root_for(*lines, "if (Is it ok?) then (y)", ":Go;",
                                    "endif"))

      expect(extent(hexagon, 0))
        .to be_within(0.01).of(trebuchet("Is it ok?", 11) + 24)
    end
  end
end
