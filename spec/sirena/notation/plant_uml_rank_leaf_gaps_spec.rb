# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

# Rank and leaf separation measured on the PlantUML JAR 1.2026.6: a rank gap
# of 60 (objects, classes), 17 more for a one-line label between the ranks
# and 15 for each further line, 35 between neighbours, a boxless WBS leaf
# 31.13 from the next.
RSpec.describe Sirena::Notation::PlantUML do
  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(described_class) }

  def render(*lines, tag: "uml")
    source = "@start#{tag}\n#{lines.join("\n")}\n@end#{tag}\n"
    REXML::Document.new(Sirena.render(source, notation: :plantuml))
  end

  def boxes(svg)
    names = %w[x y width height]
    REXML::XPath.match(svg, "//rect[@height]").map do |rect|
      names.map { |name| rect.attributes[name].to_f }
    end
  end

  def gaps_between(boxes_in_order)
    boxes_in_order.each_cons(2).map do |above, below|
      below[1] - above[1] - above[3]
    end
  end

  def objects(label)
    render("object A", "object B", "object C", "object D", "A <|-- B",
           "C .. D#{label}").then { |svg| boxes(svg) }
  end

  describe "an object diagram" do
    it "puts ranks 60 apart and neighbours 35 apart" do
      found = objects("")

      expect([gaps_between([found[0], found[1]]).first.round(2),
              (found[2][0] - found[0][0] - found[0][2]).round(2)])
        .to eq([60.0, 35.0])
    end

    it "makes room for a one-line label between the ranks" do
      expect(gaps_between(objects(" : label").first(2)).first.round(2))
        .to eq(77.0)
    end

    it "makes room for every line of a label between the ranks" do
      expect(gaps_between(objects(' : one\ntwo').first(2)).first.round(2))
        .to eq(92.0)
    end

    it "gives a label on a line inside one rank no room" do
      found = boxes(render("object A", "object B", "A -right- B : label"))

      expect(found.map { _1[1] }.uniq.size).to eq(1)
    end
  end

  describe "a class hierarchy" do
    let(:plain) do
      boxes(render("class A", "class B", "class C", "A <|-- B", "A <|-- C"))
    end

    it "keeps ranks 60 apart" do
      expect(gaps_between(plain.first(2)).first.round(2)).to eq(60.0)
    end

    it "makes room for a labelled relation between the ranks" do
      found = boxes(render("class A", "class B", "class C", "A <|-- B : label",
                           "A <|-- C"))

      expect(gaps_between(found.values_at(0, 1)).first.round(2)).to eq(77.0)
    end

    it "makes room for every line of a label" do
      found = boxes(render("class A", "class B", "class C",
                           'A <|-- B : one\ntwo', "A <|-- C"))

      expect(gaps_between(found.values_at(0, 1)).first.round(2)).to eq(92.0)
    end

    it "ignores the label of a relation inside one rank" do
      found = boxes(render("class A", "class B", "class C", "A <|-- C",
                           "A - B : label"))

      expect([found[0][1], gaps_between([found[0], found[2]]).first.round(2)])
        .to eq([found[1][1], 60.0])
    end

    it "centres unequal classes and unlinked ones on their ranks" do
      found = boxes(render("class A", "class B", "A <|-- B",
                           "enum E {", "X", "Y", "}", "class F", "class G"))

      expect(found.map { |box| (box[1] + (box[3] / 2)).round(1) }.uniq.size)
        .to eq(2)
    end
  end

  describe "unlinked classes with members" do
    it "stand a node separation apart" do
      found = boxes(render("class A {", "x : int", "}", "class B {",
                           "y : int", "}"))

      expect((found[1][0] - found[0][0] - found[0][2]).round(2)).to eq(35.0)
    end
  end

  describe "a boxless WBS leaf" do
    let(:texts) do
      svg = render("* World", "** Europe", "***_ England", "***_ Germany",
                   "***_ Spain", tag: "wbs")
      REXML::XPath.match(svg, "//text").to_h do |text|
        [text.text, text.attributes["y"].to_f]
      end
    end

    it "keeps one pixel above and below its text" do
      expect([texts["Germany"] - texts["England"],
              texts["Spain"] - texts["Germany"]].map { _1.round(2) })
        .to eq([31.13, 31.13])
    end
  end

  describe "a boxless mindmap leaf" do
    it "keeps the standard room around its text" do
      svg = render("* Root", "**_ One", "**_ Two", tag: "mindmap")
      ys = REXML::XPath.match(svg, "//text").to_h do |text|
        [text.text, text.attributes["y"].to_f]
      end

      expect((ys["Two"] - ys["One"]).round(2)).to eq(56.49)
    end
  end
end
