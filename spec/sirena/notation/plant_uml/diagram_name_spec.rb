# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

RSpec.describe Sirena::Notation::PlantUML::DiagramName do
  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  # family => [tag, body]: one source per diagram family the notation reads.
  families = {
    "class" => ["uml", "class A\nA --> B"],
    "sequence" => ["uml", "A -> B : hi"],
    "activity" => ["uml", ":a;\n:b;"],
    "usecase" => ["uml", "actor U\nusecase X\nU --> X"],
    "component" => ["uml", "[A] --> [B]"],
    "state" => ["uml", "[*] --> S1\nS1 --> [*]"],
    "entity" => ["uml", "entity E {\n id : int\n}"],
    "object" => ["uml", "object o1\nobject o2\no1 --> o2"],
    "timing" => ["uml", "robust \"W\" as W\n@0\nW is a\n@1\nW is b"],
    "mindmap" => ["mindmap", "* a\n** b"],
    "wbs" => ["wbs", "* a\n** b"],
    "gantt" => ["gantt", "[T] lasts 2 days"],
    "ebnf" => ["ebnf", "a = \"x\";"],
    "network" => ["nwdiag", "nwdiag {\n network n {\n a;\n }\n}"],
  }

  def draw(text) = Sirena.render(text, notation: :plantuml)

  def source(tag, body, opener = "@start#{tag}")
    "#{opener}\n#{body}\n@end#{tag}\n"
  end

  families.each do |family, (tag, body)|
    context "with a #{family} diagram" do
      let(:plain) { source(tag, body) }

      it "draws a named opener exactly as the unnamed one" do
        named = source(tag, body, "@start#{tag} foo")

        expect(draw(named)).to eq(draw(plain))
      end

      it "draws an id opener exactly as the unnamed one" do
        named = source(tag, body, "@start#{tag}(id=foo)")

        expect(draw(named)).to eq(draw(plain))
      end

      it "exposes the name on the parsed result" do
        parsed = Sirena::Notation::PlantUML.parse(
          source(tag, body, "@start#{tag} foo"),
        )

        expect(parsed.name).to eq("foo")
      end

      it "exposes no name for an unnamed opener" do
        expect(Sirena::Notation::PlantUML.parse(plain).name).to be_nil
      end
    end
  end

  describe ".read" do
    it "reads the id form" do
      expect(described_class.read("@startuml(id=foo)\n@enduml")).to eq("foo")
    end

    it "keeps path-like, spaced and quoted names raw" do
      expect(described_class.read("@startuml ../evil \"q\" a.b\n@enduml"))
        .to eq("../evil \"q\" a.b")
    end

    it "prefers the trailing text over the id" do
      expect(described_class.read("@startuml(id=one) two\n@enduml"))
        .to eq("two")
    end

    it "skips a byte order mark, blank lines and comments" do
      expect(described_class.read("﻿\n' c\n@startuml foo\n@enduml"))
        .to eq("foo")
    end

    it "reads nothing from an empty id or a bare opener" do
      expect([described_class.read("@startuml()\n"),
              described_class.read("@startuml\n")]).to all(be_nil)
    end

    it "reads nothing from a source with no opener" do
      expect(described_class.read("A -> B")).to be_nil
    end

    it "reads nothing from a name that is not valid UTF-8" do
      expect(described_class.read("@startuml \xFF\n@enduml".b)).to be_nil
    end

    it "reads nothing from a tag fused to a word" do
      expect(described_class.read("@startUML foo")).to be_nil
    end
  end
end
