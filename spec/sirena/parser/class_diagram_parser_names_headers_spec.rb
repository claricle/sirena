# frozen_string_literal: true

require "spec_helper"

# How a class is named and how the diagram is headed: backticks, hyphens,
# generics on relationship ends and members, the `:::css` shorthand and `classDiagram-v2`.
# Every accept/reject below was checked against mmdc 11.12.0.
RSpec.describe Sirena::Parser::ClassDiagramParser, "#parse names and headers" do
  let(:parser) { described_class.new }

  describe "class names" do
    {
      "a backticked name" => ["class `Car`", "Car"],
      "a backticked name with a space" => ["class `A B`", "A B"],
      "a backticked name with punctuation" => ["class `a-b.c$ d`", "a-b.c$ d"],
      "a hyphenated name" => ["class Ca-r", "Ca-r"],
      "a name with a hyphen before a digit" => ["class C1-2", "C1-2"],
      "a name that starts with a digit" => ["class 1", "1"],
      "a non-ASCII name" => ["class é", "é"],
      "a dotted name" => ["class A.B.C", "A.B.C"],
      "a backticked standalone class" => ["`Car`", "Car"],
      "a hyphenated standalone class" => ["Ca-r", "Ca-r"]
    }.each do |name, (statement, id)|
      it "reads #{name} as the id #{id.inspect}" do
        diagram = parser.parse("classDiagram\n#{statement}\n")

        expect(diagram.entities.map(&:id)).to eq([id])
      end
    end

    it "treats `Car` and Car as one class" do
      source = "classDiagram\nclass `Car`\nCar --> Wheel\n`Car` : +go()\n"
      diagram = parser.parse(source)

      expect(diagram.entities.map(&:id)).to eq(%w[Car Wheel])
    end

    it "keeps a hyphenated name inside a relationship" do
      diagram = parser.parse("classDiagram\nA-B --> C-D\n")

      expect(diagram.relationships.map { |r| [r.from_id, r.to_id] })
        .to eq([%w[A-B C-D]])
    end

    it "lets a hyphen that starts an operator end the name" do
      diagram = parser.parse("classDiagram\nA-x-->B\nC-y--D\n")

      expect(diagram.relationships.map { |r| [r.from_id, r.to_id] })
        .to eq([%w[A-x B], %w[C-y D]])
    end

    it "reads `A..>B` as a dependency, not a name with dots" do
      diagram = parser.parse("classDiagram\nA..>B\n")

      expect(diagram.relationships.map(&:relationship_type))
        .to eq(["dependency"])
    end

    {
      "an empty backtick name" => "class ``",
      "text after a backticked name" => "class `a`b",
      "a trailing dot" => "class A.",
      "a leading dot" => "class .A",
      "a doubled dot" => "class A..B",
      "a dollar sign" => "class A$",
      "an ampersand" => "class A&B",
      "an unclosed backtick" => "class `A"
    }.each do |name, statement|
      it "rejects #{name}, as mmdc does" do
        expect { parser.parse("classDiagram\n#{statement}\n") }
          .to raise_error(Sirena::Parser::ParseError)
      end
    end
  end

  it "keeps a name that spans lines inside backticks, as mmdc does" do
    diagram = parser.parse("classDiagram\nclass `A\nB`\n")

    expect(diagram.entities.map(&:id)).to eq(["A\nB"])
  end

  it "reports a binary-tagged source with non-ASCII bytes as a ParseError" do
    source = "classDiagram\nclass ".b + "\xFF\n".b

    expect { parser.parse(source) }.to raise_error(Sirena::Parser::ParseError)
  end

  it "reports invalid UTF-8 in a UTF-8-tagged source as a ParseError" do
    source = ("classDiagram\nclass ".b + "\xFF\n".b).force_encoding(Encoding::UTF_8)

    expect { parser.parse(source) }.to raise_error(Sirena::Parser::ParseError)
  end

  it "resolves a standalone class inside a namespace to its declaration" do
    diagram = parser.parse("classDiagram\nnamespace N {\nclass `A B`\n`A B`\n}\n")

    expect(diagram.entities.map(&:id)).to eq(["N.A B"])
  end

  it "keeps generic-looking text in a backticked name when a generic is applied" do
    diagram = parser.parse("classDiagram\nclass `A~B~`~T~\n")

    expect(diagram.entities.map { |e| [e.id, e.name] }).to eq([["A~B~", "A~B~~T~"]])
  end

  it "reads a direction on the plain header" do
    expect(parser.parse("classDiagram LR\nclass A\n").direction).to eq("LR")
  end

  describe "generics on a class mention" do
    it "shows the generic on the name in a relationship" do
      diagram = parser.parse("classDiagram\nClass1~T~ <|-- Class02\n")

      expect(diagram.entities.map(&:name)).to eq(%w[Class1~T~ Class02])
    end

    it "reads the generic on the target of a relationship" do
      diagram = parser.parse("classDiagram\nA --> B~T~\n")

      expect(diagram.entities.map(&:name)).to eq(%w[A B~T~])
    end

    it "reads a generic on a backticked name" do
      diagram = parser.parse("classDiagram\nclass `Car`~T~\nDriver -- `Car`\n")

      expect(diagram.entities.map(&:name)).to eq(%w[Car~T~ Driver])
    end

    it "reads a generic on a standalone class and a colon member" do
      diagram = parser.parse("classDiagram\nA~T~\nB~U~ : +x\n")

      expect(diagram.entities.map(&:name)).to eq(%w[A~T~ B~U~])
    end

    it "does not stack a generic when the same class is mentioned twice" do
      diagram = parser.parse("classDiagram\nA~T~ --> B\nA~T~ --> C\n")

      expect(diagram.entities.first.name).to eq("A~T~")
    end

    it "lets a later generic replace an earlier one" do
      diagram = parser.parse("classDiagram\nclass A~T~\nA~U~ --> B\n")

      expect(diagram.entities.first.name).to eq("A~U~")
    end

    it "keeps an explicit label over a generic on a later mention" do
      diagram = parser.parse("classDiagram\nclass A[\"Label\"]\nA~T~ --> B\n")

      expect(diagram.entities.first.name).to eq("Label")
    end

    # Keep: a guard that the new generic slot does not swallow trailing text.
    it "rejects text glued to a generic" do
      expect { parser.parse("classDiagram\nA~T~ B\n") }
        .to raise_error(Sirena::Parser::ParseError)
    end
  end

  describe "the :::css shorthand" do
    {
      "after the name" => "class Class01:::exClass",
      "with spaces around it" => "class Class01 ::: exClass",
      "after a generic" => "class A~T~:::s",
      "after a label" => 'class C1["Class 1"]:::s',
      "before a body" => "class A:::s {\n+x\n}",
      "with a label and a body" => "class C1[\"L\"]:::s {\n+x\n}",
      "on a backticked name" => "class `A`:::s",
      "starting with a digit" => "class A:::1s",
      "starting with an underscore" => "class A:::_s"
    }.each do |name, statement|
      it "parses it #{name} as one class" do
        diagram = parser.parse("classDiagram\n#{statement}\n")

        expect(diagram.entities.size).to eq(1)
      end
    end

    it "keeps the members of a class that has the shorthand" do
      diagram = parser.parse("classDiagram\nclass A:::s {\n+x\n+go()\n}\n")

      expect([diagram.entities.first.attributes.size,
              diagram.entities.first.class_methods.size]).to eq([1, 1])
    end

    it "does not make the css class a class" do
      diagram = parser.parse("classDiagram\nclass A:::pink\nclassDef pink fill:#f9f\n")

      expect(diagram.entities.map(&:id)).to eq(["A"])
    end

    it "parses the shorthand inside a namespace" do
      diagram = parser.parse("classDiagram\nnamespace N {\nclass A:::s\n}\n")

      expect(diagram.entities.map(&:id)).to eq(["N.A"])
    end

    # Keep: mmdc rejects each of these; they guard the new shorthand from
    # growing a stereotype, a second shorthand or a looser name.
    {
      "a stereotype after it" => "class A:::s <<i>>",
      "a stereotype before it" => "class A <<i>>:::s",
      "a label after it" => 'class A:::s ["l"]',
      "a second shorthand" => "class A:::a:::b",
      "an empty name" => "class A:::",
      "a hyphen in the name" => "class A:::s-t",
      "a dot in the name" => "class A:::s.t",
      "a quoted name" => 'class A:::"s"',
      "the shorthand on a bare class" => "A:::s"
    }.each do |name, statement|
      it "rejects #{name}, as mmdc does" do
        expect { parser.parse("classDiagram\n#{statement}\n") }
          .to raise_error(Sirena::Parser::ParseError)
      end
    end
  end

  describe "the classDiagram-v2 header" do
    it "parses a diagram headed classDiagram-v2" do
      diagram = parser.parse("classDiagram-v2\nclass A\nA --> B\n")

      expect(diagram.entities.map(&:id)).to eq(%w[A B])
    end

    it "takes a direction statement after the header" do
      diagram = parser.parse("classDiagram-v2\ndirection LR\nclass A\n")

      expect(diagram.direction).to eq("LR")
    end

    it "does not read the header text as a class" do
      diagram = parser.parse("classDiagram-v2\nclass A\n")

      expect(diagram.entities.map(&:id)).to eq(["A"])
    end

    it "renders through the engine, which detects the v2 header" do
      expect(Sirena.render("classDiagram-v2\nclass A\n")).to include("<svg")
    end

    {
      "a direction on the header line" => "classDiagram-v2 LR\nclass A\n",
      "an unknown suffix" => "classDiagram-v2x\nclass A\n",
      "another version" => "classDiagram-v3\nclass A\n",
      "a suffix on the plain header" => "classDiagramX\nclass A\n",
      "a direction glued to the plain header" => "classDiagramLR\nclass A\n",
      "a backticked class glued to the header" => "classDiagram`A`\n",
      "a backticked class after the header on its line" => "classDiagram `A`\n"
    }.each do |name, source|
      it "rejects #{name}, as mmdc does" do
        expect { parser.parse(source) }
          .to raise_error(Sirena::Parser::ParseError)
      end
    end
  end
end
