# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"
require_relative "plant_uml_salt/salt_helpers"

# Requiring PlantUML registers it; restore the suite baseline.
Sirena::Notation.send(:entries).delete(:plantuml)

RSpec.describe Sirena::Notation::PlantUMLSalt do
  include SaltHelpers

  describe "identity" do
    it "is registered by require sirena as :plantuml_salt" do
      expect(Sirena::Notation.fetch(:plantuml_salt)).to eq(described_class)
    end

    it "reads .salt and leaves .puml to PlantUML" do
      expect([described_class.extensions,
              Sirena::Notation::PlantUML.extensions])
        .to eq([[".salt"], [".puml"]])
    end
  end

  describe "#claims?" do
    {
      "a bare opener" => "@startsalt\n{\n}\n@endsalt",
      "a named opener after comments" => "'c\n\n @startsalt x\n",
      "a BOM-prefixed opener" => "\xEF\xBB\xBF@startsalt\n",
    }.each do |label, source|
      it "claims #{label}" do
        expect(described_class.claims?(source)).to be(true)
      end
    end

    ["@startuml\nclass A\n", "@startsaltx\n", "graph TD\nA-->B", "\xFF\xFE"]
      .each do |source|
      it "does not claim #{source.inspect}" do
        expect(described_class.claims?(source)).to be(false)
      end
    end

    it "is not claimed by PlantUML" do
      salt = "@startsalt\n{\n}\n"
      expect(Sirena::Notation::PlantUML.claims?(salt)).to be(false)
    end
  end

  describe "routing" do
    it "renders @startsalt through the salt notation with no option" do
      svg = Sirena.render("@startsalt\n{\n[Go]\n}\n@endsalt")
      expect(svg_texts(svg)).to eq(["Go"])
    end

    it "renders a .salt path through the salt notation" do
      svg = Sirena.render("@startsalt\n{\n[Go]\n}", path: "a.salt")
      expect(svg_texts(svg)).to eq(["Go"])
    end

    context "with PlantUML registered" do
      include_context "with an isolated notation registry"

      before do
        Sirena::Notation.send(:entries).delete(:plantuml)
        Sirena::Notation.register(Sirena::Notation::PlantUML)
      end

      it "leaves @startuml with PlantUML" do
        uml = "@startuml\nclass A\n@enduml"
        expect(Sirena::Notation.resolve(explicit: nil, path: nil, source: uml))
          .to eq(Sirena::Notation::PlantUML)
      end

      it "sends @startsalt to the salt notation" do
        expect(Sirena::Notation.resolve(explicit: nil, path: nil,
                                        source: "@startsalt\n"))
          .to eq(described_class)
      end
    end
  end

  describe "#parse" do
    it "refuses a source with no @startsalt" do
      expect { described_class.parse("{\n[Go]\n}") }
        .to raise_error(Sirena::Engine::DiagramTypeError, /@startsalt/)
    end
  end

  describe "rendering" do
    let(:source) do
      "@startsalt\n{#\n<b>B</b> | <i>I</i> | <u>U</u> | [Btn]\n" \
        "(X) r | [X] c\n}\n@endsalt"
    end
    let(:svg) { Sirena.render(source) }
    let(:doc) { REXML::Document.new(svg) }

    it "marks bold as font-weight and italic as font-style" do
      weights = doc.get_elements("//text").to_h do |t|
        [t.text, [t.attributes["font-weight"], t.attributes["font-style"]]]
      end
      expect(weights.values_at("B",
                               "I")).to eq([["bold", nil], [nil, "italic"]])
    end

    it "underlines with a line and gridlines the # block" do
      expect(doc.get_elements("//line").size).to be > 3
    end

    it "draws a line between rows only for a {- block" do
      rows = "a\nb\nc\n}\n@endsalt"
      lined = Sirena.render("@startsalt\n{-\n#{rows}")
      plain = Sirena.render("@startsalt\n{\n#{rows}")
      counts = [lined, plain].map { |out| REXML::Document.new(out).get_elements("//line").size }
      expect(counts).to eq([2, 0])
    end

    it "draws a droplist as a box with a trailing arrow" do
      out = Sirena.render("@startsalt\n{\n^pick^\n}\n@endsalt")
      expect(svg_texts(out)).to eq(%w[pick v])
    end

    it "escapes literal angle text" do
      out = Sirena.render("@startsalt\n{\n<P>\n}\n@endsalt")
      expect(svg_texts(out)).to eq(["<P>"])
    end

    it "draws a stray line outside any block as text instead of raising" do
      expect(svg_texts(Sirena.render("@startsalt\nhello\n@endsalt")))
        .to eq(["hello"])
    end
  end
end
