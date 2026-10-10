# frozen_string_literal: true

require "spec_helper"

module ClassDiagramTextLabelHelpers
  def entities(source)
    parser.parse(source).entities.map { |e| [e.id, e.name] }
  end

  def relationship(source)
    parser.parse("classDiagram\n#{source}").relationships.first
  end

  def attribute_values(source)
    parser.parse(source).find_entity("Animal").attributes.map do |attribute|
      [attribute.name, attribute.type, attribute.visibility]
    end
  end

  def method_values(source)
    methods = parser.parse(source).find_entity("Animal").class_methods
    first = methods.first
    last = methods.last
    [methods.length, first.name, first.visibility,
     last.name, last.parameters, last.return_type]
  end
end

RSpec.describe Sirena::Parser::ClassDiagram do
  include ClassDiagramTextLabelHelpers

  let(:parser) { described_class.new }

  describe "#parse" do
    it "parses simple class diagram with two classes" do
      diagram = parser.parse("classDiagram\nAnimal <|-- Dog")
      expect(diagram).to be_a(Sirena::Diagram::ClassDiagram).and(
        have_attributes(entities: have_attributes(length: 2),
                        relationships: have_attributes(length: 1)),
      )
    end

    it "parses inheritance relationship" do
      expect(relationship("Animal <|-- Dog")).to have_attributes(
        from_id: "Dog", to_id: "Animal", relationship_type: "inheritance",
      )
    end

    it "parses composition relationship" do
      expect(relationship("Car *-- Engine")).to have_attributes(
        relationship_type: "composition",
      )
    end

    it "parses aggregation relationship" do
      expect(relationship("Team o-- Player")).to have_attributes(
        relationship_type: "aggregation",
      )
    end

    it "parses association relationship" do
      expect(relationship("Student -- Course")).to have_attributes(
        relationship_type: "association",
      )
    end

    it "parses a mixed aggregation/inheritance relationship (corpus 044/019)" do
      expect(relationship("Animal o--|> Zebra")).to have_attributes(
        from_id: "Animal", to_id: "Zebra", start_marker: "aggregation",
        end_marker: "inheritance", dashed: false
      )
    end

    it "parses a mixed dependency/composition relationship (corpus 118/091)" do
      expect(relationship("Class19 <--* Class20")).to have_attributes(
        from_id: "Class19", to_id: "Class20", start_marker: "dependency",
        end_marker: "composition", dashed: false
      )
    end

    it "parses a dashed aggregation relationship (corpus 121/094)" do
      expect(relationship("Class1 o.. Class02")).to have_attributes(
        start_marker: "aggregation", end_marker: nil, dashed: true,
      )
    end

    it "parses a double-sided composition relationship (corpus 122/095)" do
      expect(relationship("Class1 *--* Class02")).to have_attributes(
        start_marker: "composition", end_marker: "composition", dashed: false,
      )
    end

    # H2: mermaid defines two-way relations structurally as
    # [Relation Type][Link][Relation Type]
    # (https://mermaid.js.org/syntax/classDiagram#two-way-relations), not
    # as a fixed list. mermaid's own documented example, plus two
    # combinations the branch's earlier 4-entry hardcoded table never had.
    it "parses mermaid's own two-way relation example (Animal <|--|> Zebra)" do
      expect(relationship("Animal <|--|> Zebra")).to have_attributes(
        from_id: "Animal", to_id: "Zebra", start_marker: "inheritance",
        end_marker: "inheritance", dashed: false
      )
    end

    it "parses a two-way aggregation/dependency relationship absent from the " \
       "old table" do
      expect(relationship("Animal o--< Zebra")).to have_attributes(
        start_marker: "aggregation", end_marker: "dependency", dashed: false,
      )
    end

    it "parses a dashed two-way composition/inheritance relationship absent " \
       "from the old table" do
      expect(relationship("Animal *..|> Zebra")).to have_attributes(
        start_marker: "composition", end_marker: "inheritance", dashed: true,
      )
    end

    it "parses class with stereotype" do
      diagram = parser.parse("classDiagram\nclass Drawable <<interface>>")
      expect(diagram.find_entity("Drawable")).to have_attributes(
        stereotype: "interface",
      )
    end

    it "parses class with attributes" do
      source = "classDiagram\nclass Animal {\n  +name: string\n  -age: int\n}"
      expect(attribute_values(source)).to eq(
        [["name", "string", "public"], ["age", "int", "private"]],
      )
    end

    it "parses class with methods" do
      source = "classDiagram\nclass Animal {\n  +breathe()\n  " \
               "+move(x: int, y: int): void\n}"
      expected = [2, "breathe", "public", "move", "x: int, y: int", "void"]
      expect(method_values(source)).to eq(expected)
    end

    it "parses relationship with cardinality" do
      expect(relationship('Student "1" -- "0..*" Course')).to have_attributes(
        source_cardinality: "1", target_cardinality: "0..*",
      )
    end

    it "parses relationship with label" do
      expect(relationship("Student -- Course : enrolls in")).to have_attributes(
        label: "enrolls in",
      )
    end

    it "parses relationship with pipe-delimited label" do
      relation = relationship('Student --|"enrolls in"| Course')
      expect(relation).to have_attributes(
        label: "enrolls in",
      )
    end

    it "parses relationship with pipe-delimited label using single quotes" do
      relation = relationship("Student --|'enrolls in'| Course")
      expect(relation).to have_attributes(
        label: "enrolls in",
      )
    end

    it "parses arrow relationship with pipe-delimited label" do
      expect(relationship('ClassA -->|"uses"| ClassB')).to have_attributes(
        label: "uses", relationship_type: "association",
      )
    end

    it "parses aggregation with pipe-delimited label" do
      expect(relationship('Team o--|"contains"| Player')).to have_attributes(
        label: "contains", relationship_type: "aggregation",
      )
    end

    it "parses composition with pipe-delimited label" do
      expect(relationship('Car *--|"has"| Engine')).to have_attributes(
        label: "has", relationship_type: "composition",
      )
    end

    it "parses relationship with cardinality and pipe-delimited label" do
      source = 'Student "1" --|"enrolls in"| "0..*" Course'
      expect(relationship(source)).to have_attributes(
        source_cardinality: "1", target_cardinality: "0..*",
        label: "enrolls in"
      )
    end

    it "parses class diagram with direction" do
      diagram = parser.parse("classDiagram TB\nAnimal <|-- Dog")
      expect(diagram.direction).to eq("TB")
    end

    # Clause order matters and ours was inverted. Each of these is checked
    # against mmdc 11.12.0 rather than against what looks reasonable.
    describe "class text labels" do
      let(:stereotype_forms) do
        ['class C1["L"] <<interface>>', 'class Animal~T~["L"] <<svc>>']
      end

      it "uses the label for display and keeps the id" do
        expect(entities(%(classDiagram\n class C1["Class One"]\n)))
          .to eq([["C1", "Class One"]])
      end

      it "lets a label win over the generic, as mermaid does" do
        expect(entities(%(classDiagram\n class Animal~T~["A label"]\n)))
          .to eq([["Animal", "A label"]])
      end

      it "still appends the generic when there is no label" do
        expect(entities(%(classDiagram\n class Animal~T~\n)))
          .to eq([["Animal", "Animal~T~"]])
      end

      # mmdc 11.12.0 rejects `class C1[]` with "Expecting 'STR', got 'SQE'",
      # and rejects single quotes with "got 'PUNCTUATION'". 20 corpus cases
      # use the empty form with no sidecar, and their test names say they
      # should have a label — the content was lost in extraction, so accepting
      # it would be over-acceptance against damaged input.
      it "rejects an empty label, as mermaid does" do
        expect { parser.parse(%(classDiagram\n class C1[]\n)) }
          .to raise_error(Sirena::Parser::ParseError)
      end

      it "rejects a single-quoted label, as mermaid does" do
        expect { parser.parse(%(classDiagram\n class C1['L']\n)) }
          .to raise_error(Sirena::Parser::ParseError)
      end

      it "allows spaces inside the brackets, as mermaid does" do
        expect(entities(%(classDiagram\n class C1[ "L" ]\n)))
          .to eq([["C1", "L"]])
      end

      # common.rb's quoted_string has a backslash-escape branch that swallowed
      # \" and made us accept this; mmdc rejects it with
      # "Expecting 'SQE', got 'ALPHA'". The label uses its own string rule so
      # 15 other grammars keep the escape.
      it "rejects a backslash-escaped quote, as mermaid does" do
        expect { parser.parse(%(classDiagram\n class C1["a\\"b"]\n)) }
          .to raise_error(Sirena::Parser::ParseError)
      end

      it "still swallows a bracket inside the label" do
        expect(entities(%(classDiagram\n class C4["With [Brackets]"]\n)))
          .to eq([["C4", "With [Brackets]"]])
      end

      # The generic must not append to a label set by an EARLIER declaration.
      # This produced `Label~T~` where mmdc renders `Label`.
      it "keeps a label when a later declaration adds a generic" do
        source = %(classDiagram\n class C1["Label"]\n class C1~T~\n)

        expect(entities(source)).to eq([["C1", "Label"]])
      end

      it "keeps a label declared after the generic" do
        source = %(classDiagram\n class C1~T~\n class C1["Label"]\n)

        expect(entities(source)).to eq([["C1", "Label"]])
      end

      it "labels a class already created by an earlier relationship" do
        source = %(classDiagram\n C1 --> C2\n class C1["Later"]\n)

        expect(entities(source)).to eq([["C1", "Later"], ["C2", "C2"]])
      end

      it "accepts a label alongside a stereotype" do
        results = stereotype_forms.map do |form|
          parser.parse("classDiagram\n    #{form}\n")
        end
        expect(results).to all(be_a(Sirena::Diagram::ClassDiagram))
      end

      # mmdc accepts generic-then-stereotype and rejects the reverse. Ours was
      # the wrong way round, so these pin the corrected order.
      it "accepts the generic before the stereotype" do
        expect { parser.parse(%(classDiagram\n class C1~T~<<iface>>\n)) }
          .not_to raise_error
      end

      it "rejects orderings mermaid rejects" do
        ['class C1["L"]~T~', "class C1<<iface>>~T~"].each do |form|
          expect { parser.parse("classDiagram\n    #{form}\n") }
            .to raise_error(Sirena::Parser::ParseError), form
        end
      end
    end

    it "raises ParseError for invalid syntax" do
      source = "invalid syntax"
      expect { parser.parse(source) }.to raise_error(
        Sirena::Parser::ParseError,
      )
    end
  end

  describe "#parse names inside a namespace" do
    it "leaves a dotted class name unqualified" do
      source = "classDiagram\n  namespace N {\n    class A.B\n  }\n"

      expect(entities(source)).to eq([["A.B", "A.B"]])
    end
  end
end
