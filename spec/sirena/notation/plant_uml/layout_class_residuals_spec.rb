# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

# Geometry is measured from PlantUML 1.2026.6 (the pinned reference).
RSpec.describe Sirena::Notation::PlantUML::Layout do
  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  def render(body)
    source = "@startuml\n#{body}\n@enduml\n"
    REXML::Document.new(Sirena.render(source, notation: :plantuml))
  end

  def group(document, id)
    REXML::XPath.first(document, "//g[@id='#{id}']")
  end

  def box_top(document, name)
    REXML::XPath.first(group(document, "class-#{name}"), "rect")
      .attributes["y"].to_f
  end

  def paths(document)
    REXML::XPath.match(document, "//g[starts-with(@id,'relation-')]/path")
      .map { |path| path.attributes["d"] }
  end

  describe "a class body split by separators" do
    let(:foo) do
      render("class Foo1 {\n  a\n  ..\n  b\n  --\n  c\n}")
    end

    it "has no empty method compartment under the last group" do
      rect = REXML::XPath.first(group(foo, "class-Foo1"), "rect")

      expect(rect.attributes["height"].to_f).to be_within(0.01).of(105.4648)
    end

    it "draws only the header rule and the two separators" do
      lines = REXML::XPath.match(group(foo, "class-Foo1"), "line")

      expect(lines.size).to eq(3)
    end

    it "keeps the empty method compartment of a body without separators" do
      plain = render("class Foo1 {\n  a\n}")
      rect = REXML::XPath.first(group(plain, "class-Foo1"), "rect")

      expect(rect.attributes["height"].to_f).to be_within(0.01).of(64.4883)
    end
  end

  describe "a note with an image" do
    let(:note) do
      render("class Foo\nnote as N1\n  hosted by <img:a.jpg>\nend note")
    end

    it "prints PlantUML's undecodable-image text in monospace" do
      span = REXML::XPath.first(note, "//tspan[@font-family='monospace']")

      expect(span&.text).to eq("(Cannot decode)")
    end
  end

  describe "bracketed link styles" do
    let(:diagram) do
      render(<<~BODY)
        class foo
        class bar
        bar1 : [#red,thickness=1]
        bar2 : [#red,dashed,thickness=2]
        bar3 : [#green,dashed,thickness=4]
        bar4 : [#blue,dotted,thickness=8]
        bar5 : [#blue,plain,thickness=16]
        foo --> bar
        foo -[#red,thickness=1]-> bar1
        foo -[#red,dashed,thickness=2]-> bar2
        foo -[#green,dashed,thickness=4]-> bar3
        foo -[#blue,dotted,thickness=8]-> bar4
        foo -[#blue,plain,thickness=16]-> bar5
      BODY
    end

    it "curves a styled link that runs shallow across a rank" do
      expect(paths(diagram).grep(/ C /).size).to be >= 1
    end

    it "leaves an unstyled link on its chord" do
      expect(paths(diagram).grep(/\AM [^CQ]+ L [^CQ]+\z/).size).to be >= 1
    end
  end

  describe "labels on bracketed link styles" do
    let(:diagram) do
      render(<<~BODY)
        class foo
        class bar1
        class bar2
        class bar3
        class bar4
        class bar5
        bar1 : [#red,thickness=1]
        bar2 : [#red,dashed,thickness=2]
        bar3 : [#green,dashed,thickness=4]
        bar4 : [#blue,dotted,thickness=8]
        bar5 : [#blue,plain,thickness=16]
        foo -[#red,thickness=1]-> bar1 : one
        foo -[#red,dashed,thickness=2]-> bar2 : two
        foo -[#green,dashed,thickness=4]-> bar3 : three
        foo -[#blue,dotted,thickness=8]-> bar4 : thin
        foo -[#blue,plain,thickness=16]-> bar5 : thick
      BODY
    end

    def label(text)
      REXML::XPath.first(diagram, "//text[text()='#{text}']")
    end

    def curve_y(label, at)
      path = label.parent.elements["path"].attributes["d"]
      ys = path.scan(/-?\d+\.?\d*/).map(&:to_f).each_slice(2).map(&:last)
      ys.zip(bezier_weights(at)).sum { |value, weight| value * weight }
    end

    def bezier_weights(at)
      rest = 1 - at
      [rest**3, 3 * (rest**2) * at, 3 * rest * (at**2), at**3]
    end

    it "lifts a label clear of the thick curve it names" do
      thick = label("thick")

      expect(thick.attributes["y"].to_f).to be < curve_y(thick, 0.65) - 8.0
    end

    it "starts a label where the curve runs away below it" do
      expect(label("thick").attributes["text-anchor"]).to eq("start")
    end

    it "ends a label where a rising curve runs away below it" do
      expect(label("one").attributes["text-anchor"]).to eq("end")
    end

    it "draws the thickest link first so a thin link's label stays on top" do
      groups = REXML::XPath.match(diagram, "//g[starts-with(@id,'relation-')]")
      ids = groups.map { |node| node.attributes["id"] }

      expect(ids.first).to eq(label("thick").parent.attributes["id"])
    end
  end

  describe "labels of sloping links" do
    let(:diagram) do
      render(<<~BODY)
        class foo
        class bar1
        class bar2
        class bar3
        bar1 : a member line wide enough to push its box far left
        bar2 : [#red,dashed,thickness=2]
        bar3 : another member line wide enough to push its box right
        foo -[#red,dashed,thickness=2]-> bar2 : [#red,dashed,2]
        foo --> bar1 : tilted
        foo --> bar3
      BODY
    end

    def text_of(label)
      REXML::XPath.first(diagram, "//text[text()='#{label}']")
    end

    def line_points(label)
      path = text_of(label).parent.elements["path"].attributes["d"]
      path.scan(/-?\d+\.?\d*/).map(&:to_f).each_slice(2).to_a
    end

    def clearance
      Sirena::Notation::PlantUML::LabelClearance
    end

    it "keeps a label on the right of a sloping line past the line" do
      label = text_of("[#red,dashed,2]")
      base = label.attributes["y"].to_f
      line = line_points("[#red,dashed,2]").first(2)

      expect(label.attributes["x"].to_f)
        .to be > clearance.right_between(*line, base - 12, base)
    end

    it "lifts the label of a gentle slope clear of the line under its end" do
      label = text_of("tilted")
      end_x = label.attributes["x"].to_f + 15.0
      line_y = clearance.top_between(*line_points("tilted"), end_x, end_x)

      expect(label.attributes["y"].to_f + 3.0).to be <= line_y
    end
  end

  describe "an abstract hierarchy" do
    let(:diagram) do
      render(<<~BODY)
        abstract class AbstractList
        abstract AbstractCollection
        interface List
        interface Collection
        List <|-- AbstractList
        Collection <|-- AbstractCollection
        Collection <|- List
        AbstractCollection <|- AbstractList
      BODY
    end

    it "ranks AbstractList with AbstractCollection" do
      tops = %w[AbstractList AbstractCollection].map { |n| box_top(diagram, n) }

      expect(tops.uniq.size).to eq(1)
    end
  end
end
