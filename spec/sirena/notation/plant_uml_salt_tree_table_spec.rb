# frozen_string_literal: true

require "spec_helper"
require_relative "plant_uml_salt/salt_helpers"

# The rules below were read off PlantUML 1.2026.6 on a minimal tree
# (`+ A / ++ B / +++ C / ++ D`): every `{T` variant draws the same grey
# node marks and elbows, and the modifier alone adds rules.
RSpec.describe Sirena::Notation::PlantUMLSalt do
  include SaltHelpers

  let(:grey) { "#888888" }

  def salt(modifier, rows = tree_rows)
    "@startsalt\n{\n{#{modifier}\n#{rows}\n}\n}\n@endsalt"
  end

  def tree_rows
    "+ <b>A</b> | x | \"quoted\"\n++ B | y | plain\n" \
      "+++ C | z | \"q2\"\n++ D | w | v"
  end

  def elements(svg, name)
    REXML::Document.new(svg).get_elements("//#{name}")
  end

  def attrs(element, *names)
    names.map { |name| element.attributes[name] }
  end

  def lines(svg)
    elements(svg, "line").map do |l|
      attrs(l, "x1", "y1", "x2", "y2").map { |v| v.to_f.round(1) }
    end
  end

  def vertical_bars(svg)
    lines(svg).select { |x1, _y1, x2, _y2| x1 == x2 }.map(&:first)
  end

  def horizontal_rules(svg)
    lines(svg).select { |_x1, y1, _x2, y2| y1 == y2 }.map { |l| l[1] }
  end

  describe "tree connectors" do
    let(:svg) { Sirena.render(salt("T")) }

    it "marks only rows that have children, in grey" do
      marks = elements(svg, "rect")
      expect(marks.map { |m| [m.attributes["x"].to_f, m.attributes["stroke"]] })
        .to eq([[9.0, grey], [19.0, grey]])
    end

    it "gives a node mark a two-pixel square" do
      mark = elements(svg, "rect").first
      expect(attrs(mark, "width", "height")).to eq(%w[2.0 2.0])
    end

    it "drops an elbow from each parent to each child" do
      expect(lines(svg)).to eq(
        [[10.0, 15.1, 10.0, 27.2], [10.0, 27.2, 18.0, 27.2],
         [20.0, 29.2, 20.0, 41.3], [20.0, 41.3, 28.0, 41.3],
         [10.0, 15.1, 10.0, 55.5], [10.0, 55.5, 18.0, 55.5]],
      )
    end

    it "draws every connector in grey" do
      expect(elements(svg, "line").map { |l| l.attributes["stroke"] }.uniq)
        .to eq([grey])
    end

    it "indents each depth by ten pixels" do
      xs = elements(svg, "text").map { |t| t.attributes["x"].to_f }
      expect([xs[0], xs[3], xs[6]]).to eq([16.0, 26.0, 36.0])
    end

    it "uses tight fourteen-pixel rows" do
      ys = elements(svg, "text").map { |t| t.attributes["y"].to_f.round(1) }
      expect([ys[0], ys[3], ys[6], ys[9]]).to eq([17.6, 31.7, 45.9, 60.0])
    end

    it "attaches a skipped depth to the nearest shallower row" do
      deep = Sirena.render(salt("T", "+ A | a\n+++ B | b\n++ C | c"))
      expect(lines(deep).first(2).map(&:first)).to eq([10.0, 10.0])
    end

    it "draws no frame around a plain wrapper block" do
      expect(elements(svg, "rect").size).to eq(2)
    end
  end

  describe "rules by modifier" do
    it "draws no rules for T" do
      svg = Sirena.render(salt("T"))
      expect([vertical_bars(svg).size, horizontal_rules(svg).size])
        .to eq([3, 3])
    end

    it "draws column bars and both side bars for T!" do
      svg = Sirena.render(salt("T!"))
      expect(vertical_bars(svg).size - 3).to eq(4)
    end

    it "draws no horizontal rule for T!" do
      svg = Sirena.render(salt("T!"))
      expect(horizontal_rules(svg).size).to eq(3)
    end

    it "draws a full grid for T#" do
      svg = Sirena.render(salt("T#"))
      expect([vertical_bars(svg).size - 3, horizontal_rules(svg).size - 3])
        .to eq([4, 5])
    end

    it "draws row rules, edges included, for T-" do
      svg = Sirena.render(salt("T-"))
      expect([vertical_bars(svg).size - 3, horizontal_rules(svg).size - 3])
        .to eq([0, 5])
    end

    it "draws a grey frame for T+" do
      frame = Sirena.render(salt("T+"))
      outline = elements(frame, "rect").last
      expect(attrs(outline, "fill", "stroke"))
        .to eq(["none", grey])
    end

    it "spans the bars over the whole table" do
      svg = Sirena.render(salt("T!"))
      bar = lines(svg).last
      expect(bar.values_at(1, 3)).to eq([6.0, 62.5])
    end
  end

  describe "quoted cells" do
    it "keeps the quotes as plain text in a tree" do
      svg = Sirena.render(salt("T!"))
      expect(svg_texts(svg)).to include('"quoted"', '"q2"')
    end

    it "draws no text-field box for them" do
      svg = Sirena.render(salt("T!"))
      expect(elements(svg, "rect").size).to eq(2)
    end

    it "still reads a quoted cell outside a tree as a text field" do
      svg = Sirena.render("@startsalt\n{\n\"name\" | x\n}\n@endsalt")
      expect(elements(svg, "rect").size).to eq(1)
    end
  end

  describe "canvas" do
    it "is tight around the table, with no window frame" do
      svg = Sirena.render(salt("T!"))
      right = lines(svg).last.first
      box = REXML::Document.new(svg).root.attributes["viewBox"]
      expect(box).to eq("0 0 #{(right + 4).ceil} 69")
    end
  end

  describe "non-tree modifiers" do
    it "keeps column bars between cells for {!" do
      svg = Sirena.render("@startsalt\n{!\na | b | c\n}\n@endsalt")
      expect(vertical_bars(svg).size).to eq(2)
    end
  end

  describe "frames outside trees" do
    it "keeps the frame the JAR draws around {+" do
      svg = Sirena.render("@startsalt\n{+\n[OK] | [Cancel]\n}\n@endsalt")
      expect(elements(svg, "rect").map { |r| r.attributes["fill"] })
        .to include("none")
    end

    it "draws no frame around a plain block, as the JAR does not" do
      svg = Sirena.render("@startsalt\n{\na | b\n}\n@endsalt")
      expect(elements(svg, "rect")).to be_empty
    end
  end
end
