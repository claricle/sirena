# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"

# See the note in plant_uml_spike_spec.rb: restore the baseline registry, then
# register inside each example's isolated context.
Sirena::Notation.send(:entries).delete(:plantuml)

module PlantUmlQuotedNameHelpers
  def parse_body(body)
    Sirena::Notation::PlantUML::Parser.new.parse("@startuml\n#{body}\n@enduml\n")
  end

  def drawn(body)
    source = "@startuml\n#{body}\n@enduml\n"
    REXML::Document.new(Sirena.render(source, notation: :plantuml))
  end
end

RSpec.describe Sirena::Notation::PlantUML do
  include PlantUmlQuotedNameHelpers

  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(described_class) }

  describe "a class named in quotes" do
    it "opens the namespaces before its last dot" do
      diagram = parse_body('class "a.b.C"')

      expect([diagram.packages.map(&:id), diagram.classes.first.package])
        .to eq([%w[a a.b], "a.b"])
    end

    it "is the class a relation names in quotes" do
      diagram = parse_body("class Z\nclass \"a b\"\nZ --> \"a b\"")

      expect(diagram.relations.first.right).to eq("a b")
    end

    it "draws one title row per line of the name" do
      svg = drawn('class "A\nB"')
      texts = REXML::XPath.match(svg, "//g[@id='class-A\\nB']/text")

      expect(texts.map(&:text)).to eq(%w[A B])
    end

    it "styles only the name lines as the name" do
      svg = drawn('abstract class "A\nB"')
      weights = REXML::XPath.match(svg, "//g[@id='class-A\\nB']/text")
        .map { |text| text.attributes["font-weight"] }

      expect(weights).to eq([nil, "bold", "bold"])
    end

    it "keeps an emoji in the name" do
      svg = Sirena.render("@startuml\nclass \"A\u{1F600}\"\n@enduml\n",
                          notation: :plantuml)

      expect(svg).to include("A\u{1F600}")
    end

    {
      'class "A\\u0041"' => /unicode escape/,
      "package p {\nclass \"a.B\"\n}" => /qualified class name here/,
      'class "a..B"' => /qualified class name here/,
      "class Z\nZ --> \"a.B\"" => /first mentioned in a relation/,
      'class "A" as B' => /quoted class name/,
    }.each do |body, message|
      it "refuses #{body.inspect}" do
        expect { parse_body(body) }
          .to raise_error(described_class::UnsupportedConstructError, message)
      end
    end

    it "refuses an escape in a namespace name" do
      expect { parse_body("class \"a\\nb.C\"") }
        .to raise_error(described_class::UnsupportedConstructError,
                        /escape in a namespace name/)
    end

    it "draws a relation from a class to itself with its label" do
      svg = drawn("class \"A b\"\n\"A b\" -> \"A b\": Hello")
      texts = REXML::XPath.match(svg, "//g[@id='relation-0']/text")

      expect(texts.map(&:text)).to eq(["Hello"])
    end
  end
end
