# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

# Notes, bracketed link styles, ranked hierarchies, association-class dots and
# objects of a PlantUML class diagram, judged against the PlantUML 1.2026.6
# pictures of corpus fixtures 3-10, 3-11-3, 3-13, 3-27, 3-35-4 and 4-8.
RSpec.describe Sirena::Notation::PlantUML do
  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(described_class) }

  def svg_of(*lines)
    source = "@startuml\n#{lines.join("\n")}\n@enduml\n"
    REXML::Document.new(Sirena.render(source, notation: :plantuml))
  end

  def nodes(svg, xpath)
    REXML::XPath.match(svg, xpath)
  end

  def row_y(svg, content)
    row = nodes(svg, "//g[@id='class-A']/text").find do |text|
      text.text == content
    end
    row.attributes["y"].to_f
  end

  def note_y(svg, id)
    nodes(svg, "//g[@id='#{id}']/text").first.attributes["y"].to_f
  end

  def box_of(svg, id)
    rect = nodes(svg, "//g[@id='class-#{id}']/rect").first
    %w[x y width height].map { |name| rect.attributes[name].to_f }
  end

  describe "a hierarchy" do
    let(:svg) do
      svg_of("interface List", "class AbstractList", "class ArrayList",
             "List <|-- AbstractList", "AbstractList <|-- ArrayList")
    end

    it "puts each parent above its child" do
      tops = %w[List AbstractList ArrayList].map { |id| box_of(svg, id)[1] }

      expect(tops).to eq(tops.sort.uniq)
    end

    it "fans siblings out in one rank" do
      fan = svg_of("class P", "class A", "class B", "P <|-- A", "P <|-- B")

      expect(%w[A B].map { |id| box_of(fan, id)[1] }.uniq.size).to eq(1)
    end

    it "keeps a one-dash relation inside its rank" do
      level = svg_of("class A", "class B", "A <|- B")

      expect([box_of(level, "A")[1], box_of(level, "B")[1]].uniq.size)
        .to eq(1)
    end

    it "puts the child on top when the relation points up" do
      up = svg_of("class A", "class B", "A <|-up- B")

      expect(box_of(up, "B")[1]).to be < box_of(up, "A")[1]
    end

    it "keeps the grid for a cycle" do
      cycle = svg_of("class A", "class B", "A --> B", "B --> A")

      expect(box_of(cycle, "A")[1]).to eq(box_of(cycle, "B")[1])
    end

    it "sets classes joined to nothing aside, to the right" do
      loose = svg_of("class A", "class B", "class Loose", "A <|-- B")

      expect(box_of(loose, "Loose")[0]).to be > box_of(loose, "A")[0] +
        box_of(loose, "A")[2]
    end
  end

  describe "a note" do
    let(:svg) do
      svg_of("class Foo", "note left: On last defined class",
             "note top of Foo", "  <b>every</b> class", "end note",
             "note as N1", "  free note", "end note")
    end

    def shape(id)
      nodes(svg, "//g[@id='note-#{id}']/path").first
    end

    it "is the pale yellow of PlantUML with a folded corner" do
      expect([shape(0).attributes["fill"], shape(0).attributes["d"]])
        .to match([eq("#FEFFDD"), /L \d+(\.\d+)? \d+(\.\d+)? L/])
    end

    it "grows a tail toward its class instead of a dashed link" do
      expect([nodes(svg, "//g[starts-with(@id,'note-link')]").size,
              shape(0).attributes["d"].scan("L").size])
        .to eq([0, 7])
    end

    it "sits on the side it names" do
      foo = box_of(svg, "Foo")
      left = nodes(svg, "//g[@id='note-0']/text").first.attributes["x"].to_f
      top = nodes(svg, "//g[@id='note-1']/text").first.attributes["y"].to_f

      expect([left < foo[0], top < foo[1]]).to eq([true, true])
    end

    it "stands a free note right of every class" do
      foo = box_of(svg, "Foo")
      free = nodes(svg, "//g[@id='note-2']/text").first.attributes["x"].to_f

      expect(free).to be > foo[0] + foo[2]
    end

    it "keeps creole markup as styled text" do
      bold = nodes(svg, "//g[@id='note-1']/text/tspan").first

      expect([bold.text, bold.attributes["font-weight"]])
        .to eq(%w[every bold])
    end

    it "sits beside its member for a member note" do
      member = svg_of("class A {", "  int counter", "  int other", "}",
                      "note left of A::other", "  hi", "end note")
      note = nodes(member, "//g[@id='note-0']/text").first

      expect((note.attributes["y"].to_f - row_y(member, "int other")).abs)
        .to be < 12.0
    end
  end

  describe "a note under a class" do
    it "sits below the class box" do
      svg = svg_of("class Foo", "note bottom of Foo", "  low", "end note")
      foo = box_of(svg, "Foo")

      expect(note_y(svg, "note-0")).to be > foo[1] + foo[3]
    end

    it "moves out past an earlier note over the same class" do
      svg = svg_of("class Foo", "note top of Foo", "  one", "end note",
                   "note top of Foo", "  two", "end note")

      expect(note_y(svg, "note-1")).to be < note_y(svg, "note-0")
    end
  end

  describe "a bracketed link style" do
    let(:svg) do
      svg_of("class foo", "class bar", "class baz",
             "foo -[#red,thickness=1]-> bar : thin",
             "foo -[#blue,plain,thickness=16]-> baz : fat")
    end

    def head_width(id)
      head = nodes(svg, "//g[@id='#{id}']/polygon").first
      xs = head.attributes["points"].split.map { |p| p.split(",").first.to_f }
      xs.max - xs.min
    end

    it "grows the arrowhead with the line" do
      expect(head_width("relation-1")).to be > 3 * head_width("relation-0")
    end

    it "draws a thick head solid in the line's colour" do
      head = nodes(svg, "//g[@id='relation-1']/polygon").first

      expect([head.attributes["fill"], head.attributes["stroke-width"]])
        .to eq(%w[blue 1])
    end

    it "fans the targets out in one rank" do
      expect(%w[bar baz].map { |id| box_of(svg, id)[1] }.uniq.size).to eq(1)
    end

    it "keeps a label clear of a thick line" do
      thin = svg_of("class a", "class b", "a -[thickness=1]-> b : t")
      fat = svg_of("class a", "class b", "a -[thickness=16]-> b : t")
      label = ->(doc) { nodes(doc, "//g[@id='relation-0']/text").first }

      expect(label.call(fat).attributes["x"].to_f)
        .to be > label.call(thin).attributes["x"].to_f + 6.0
    end

    # JAR 1.2026.6: `-[#blue,#green]->` draws one green line
    it "strokes the last of several colours" do
      doc = svg_of("class a", "class b", "a -[#blue,#green]-> b")
      line = nodes(doc, "//g[@id='relation-0']/path").first

      expect(line.attributes["stroke"]).to eq("green")
    end
  end

  describe "an association class" do
    let(:svg) do
      svg_of("class Student", "class Course", "class Enrollment",
             "Student -- Course", "(Student, Course) . Enrollment")
    end

    it "marks the junction with a dot" do
      dot = nodes(svg, "//g[starts-with(@id,'dot-')]/circle").first

      expect(dot.attributes["r"].to_f).to eq(2.0)
    end

    it "runs one line through the junction" do
      ends = %w[relation-0-from relation-0-to].map do |id|
        nodes(svg, "//g[@id='#{id}']/path").first.attributes["d"].scan(/[\d.]+/)
      end

      expect(ends.first.last(2)).to eq(ends.last.first(2))
    end
  end
end
