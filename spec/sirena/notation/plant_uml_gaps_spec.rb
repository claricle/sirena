# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

# Spec helpers for the gaps closed in the sequence and class families.
module PlantUmlGapsHelpers
  FIXTURES = File.expand_path("../../fixtures/plantuml_gaps", __dir__)

  def render(body)
    Sirena.render("@startuml\n#{body}\n@enduml\n", notation: :plantuml)
  end

  def render_fixture(name)
    Sirena.render(File.read(File.join(FIXTURES, "#{name}.puml")),
                  notation: :plantuml)
  end

  def svg_texts(svg)
    REXML::XPath.match(REXML::Document.new(svg), "//text").map(&:text)
  end

  def svg_height(svg)
    REXML::Document.new(svg).root.attributes["height"].to_f
  end

  def svg_width(svg)
    REXML::Document.new(svg).root.attributes["width"].to_f
  end
end

RSpec.describe Sirena::Notation::PlantUML do
  include PlantUmlGapsHelpers

  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(described_class) }

  describe "corpus files" do
    {
      "plantuml-lrg-1-15" => %w[Alice Bob],
      "plantuml-lrg-1-19" => ["Some ~~long delay~~", "ok"],
    }.each do |name, expected|
      it "renders #{name} as valid SVG with its text",
         :aggregate_failures do
        svg = render_fixture(name)

        expect(REXML::Document.new(svg).root.name).to eq("svg")
        expect(svg_texts(svg)).to include(*expected)
      end
    end
  end

  describe "sequence note colour names" do
    it "reads aqua as PlantUML draws it" do
      svg = render("participant A\nnote left of A #aqua\nhi\nend note")

      expect(svg).to include("#00FFFF")
    end
  end

  describe "sequence delay" do
    let(:plain) { render("A -> B : one\nB -> A : two") }
    let(:delayed) { render("A -> B : one\n... later ...\nB -> A : two") }

    it "draws the text of a delay between the messages" do
      expect(svg_texts(delayed)).to include("later")
    end

    it "makes room for the delay" do
      expect(svg_height(delayed)).to be > svg_height(plain)
    end

    it "makes room for a bare delay without drawing a text" do
      bare = render("A -> B : one\n...\nB -> A : two")

      expect(svg_height(bare)).to be > svg_height(plain)
    end

    it "widens the diagram for a long delay text" do
      long = render("A -> B\n... #{'long ' * 12}...\nB -> A")

      expect(svg_width(long)).to be > svg_width(delayed)
    end

    it "still refuses spacing, which is not read" do
      expect { render("A -> B\n|||\nB -> A") }
        .to raise_error(described_class::UnsupportedConstructError,
                        /spacing/)
    end
  end

  describe "class declaration without the class word" do
    it "reads `abstract Name` as an abstract class" do
      declared = render("abstract Shape")
      spelled = render("abstract class Shape")

      expect(declared).to eq(spelled)
    end

    it "keeps `abstract` usable as a class name in a relation" do
      svg = render("class Foo\nabstract --> Foo")

      expect(svg_texts(svg)).to include("abstract")
    end
  end

  describe "class note without a target" do
    it "sits beside the class defined last" do
      beside = render("class A\nclass B\nnote left: hello")
      named = render("class A\nclass B\nnote left of B : hello")

      expect(beside).to eq(named)
    end

    it "takes text up to `end note` too" do
      beside = render("class A\nnote right\nhello\nend note")
      named = render("class A\nnote right of A\nhello\nend note")

      expect(beside).to eq(named)
    end

    it "refuses a note before any class is defined" do
      expect { render("note left: hello") }
        .to raise_error(described_class::UnsupportedConstructError,
                        /note/)
    end
  end
end
