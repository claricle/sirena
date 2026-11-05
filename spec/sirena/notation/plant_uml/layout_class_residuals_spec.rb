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
