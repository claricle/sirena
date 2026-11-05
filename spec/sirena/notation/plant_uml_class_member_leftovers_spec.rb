# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

# Member text, member order, member-note pointers and the stereotype header of
# a PlantUML class diagram, judged against PlantUML 1.2026.6 pictures of
# corpus fixtures 3-5, 3-6, 3-11-3 and of one-class probes.
RSpec.describe Sirena::Notation::PlantUML do
  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(described_class) }

  def svg_of(*lines)
    source = "@startuml\n#{lines.join("\n")}\n@enduml\n"
    REXML::Document.new(Sirena.render(source, notation: :plantuml))
  end

  def texts(svg)
    REXML::XPath.match(svg, "//text").to_h { |t| [t.text, t.attributes] }
  end

  def number(attributes, name)
    attributes[name].to_f
  end

  describe "colon spacing" do
    it "keeps the spacing the member was written with" do
      svg = svg_of("class A {", "a:int", "b: int", "c :int", "d : int",
                   "m():int", "n() : int", "}")

      expect(texts(svg).keys).to include("a:int", "b: int", "c :int",
                                         "d : int", "m():int", "n() : int")
    end

    it "keeps it through the notation IR" do
      parsed = described_class.parse("@startuml\nclass A {\na:int\n}\n@enduml")
      read = described_class::IRReader.call(parsed.diagram)
      member = read.classes.first.body.first

      expect(member.type_separator).to eq(":")
    end
  end

  describe "member order" do
    it "lists fields before methods wherever they were written" do
      svg = svg_of("class A {", "m1()", "f1", "m2()", "f2", "}")
      rows = REXML::XPath.match(svg, "//text").map(&:text)

      expect(rows).to eq(%w[A f1 f2 m1() m2()])
    end

    it "keeps the written order of a body with a rule" do
      svg = svg_of("class A {", "m1()", "--", "f1", "}")
      rows = REXML::XPath.match(svg, "//text").map(&:text)

      expect(rows).to eq(%w[A m1() f1])
    end
  end

  describe "class header geometry" do
    let(:plain) { texts(svg_of("class A {", "a : int", "m()", "}")) }

    def top(svg)
      REXML::XPath.first(svg, "//rect[@height]").attributes["y"].to_f
    end

    it "puts the name 21.29 below the top of the box" do
      svg = svg_of("class A {", "a : int", "m()", "}")
      name = number(texts(svg).fetch("A"), "y")

      expect(name - top(svg)).to be_within(0.05).of(21.291)
    end

    it "rules between fields and methods 6.95 below the last field" do
      svg = svg_of("class A {", "a : int", "m()", "}")
      field = number(texts(svg).fetch("a : int"), "y")
      rules = REXML::XPath.match(svg, "//line").map { |l| l.attributes["y1"].to_f }

      expect(rules.map { |y| (y - field).round(2) }).to include(6.95)
    end

    it "draws a stereotyped class as the jar does" do
      svg = svg_of("class A <<ste>> {", "a : int", "m()", "}")
      rows = texts(svg)
      at = rows.values_at("«ste»", "A", "a : int", "m()")
        .map { |row| (number(row, "y") - top(svg)).round(1) }

      expect(at).to eq([16.6, 32.7, 58.2, 82.6])
    end

    it "centres the stereotype and the name on each other" do
      rows = texts(svg_of("class LongerName <<ste>> {", "a : int", "}"))

      expect(number(rows.fetch("«ste»"), "x"))
        .to eq(number(rows.fetch("LongerName"), "x"))
    end
  end

  describe "a note on a member" do
    let(:source) do
      ["class A {", "{static} int counter", "+void start(int t)", "}",
       "note left of A::counter", "left", "end note",
       'note right of A::"start(int t)"', "right", "end note"]
    end
    let(:svg) { svg_of(*source) }
    let(:pointers) do
      REXML::XPath.match(svg, "//g[starts-with(@id,'note')]/path").map do |p|
        p.attributes["d"]
      end
    end

    it "points the left note at the start of the member text" do
      rows = texts(svg)
      start = number(rows.fetch("int counter"), "x")

      expect(pointers.first).to include("L #{start.round(3)} ")
        .or include("L #{start.round(2)} ")
    end

    it "finds a method named by its quoted signature" do
      rows = texts(svg)
      row = number(rows.fetch("void start(int t)"), "y") - 5.2911

      expect(pointers.last).to match(/ #{row.round(3).to_s[0, 5]}/)
    end
  end
end
