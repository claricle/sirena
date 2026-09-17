# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::Parser::ErDiagramParser do
  let(:parser) { described_class.new }

  describe '#parse' do
    it 'parses simple ER diagram with relationship' do
      source = "erDiagram\nCUSTOMER ||--o{ ORDER"
      diagram = parser.parse(source)

      expect(diagram).to be_a(Sirena::Diagram::ErDiagram)
      expect(diagram.entities.length).to eq(2)
      expect(diagram.relationships.length).to eq(1)
    end

    it 'parses non-identifying relationship' do
      source = "erDiagram\nCUSTOMER ||--o{ ORDER"
      diagram = parser.parse(source)

      rel = diagram.relationships.first
      expect(rel.from_id).to eq('CUSTOMER')
      expect(rel.to_id).to eq('ORDER')
      expect(rel.relationship_type).to eq('non-identifying')
      expect(rel.cardinality_from).to eq('one')
      expect(rel.cardinality_to).to eq('zero_or_more')
    end

    it 'parses identifying relationship' do
      source = "erDiagram\nCUSTOMER ||==o{ ORDER"
      diagram = parser.parse(source)

      rel = diagram.relationships.first
      expect(rel.relationship_type).to eq('identifying')
    end

    it 'parses entity with attributes' do
      source = <<~MERMAID
        erDiagram
        CUSTOMER {
          int id PK
          string name
          string email FK
        }
      MERMAID
      diagram = parser.parse(source)

      entity = diagram.find_entity('CUSTOMER')
      expect(entity).not_to be_nil
      expect(entity.attributes.length).to eq(3)

      attr1 = entity.attributes[0]
      expect(attr1.name).to eq('id')
      expect(attr1.attribute_type).to eq('int')
      expect(attr1.key_type).to eq('PK')

      attr2 = entity.attributes[1]
      expect(attr2.name).to eq('name')
      expect(attr2.attribute_type).to eq('string')
      expect(attr2.key_type).to be_nil

      attr3 = entity.attributes[2]
      expect(attr3.name).to eq('email')
      expect(attr3.attribute_type).to eq('string')
      expect(attr3.key_type).to eq('FK')
    end

    it 'parses one-to-one cardinality' do
      source = "erDiagram\nCUSTOMER ||--|| ADDRESS"
      diagram = parser.parse(source)

      rel = diagram.relationships.first
      expect(rel.cardinality_from).to eq('one')
      expect(rel.cardinality_to).to eq('one')
    end

    it 'parses zero-or-one cardinality' do
      source = "erDiagram\nCUSTOMER ||--}o ADDRESS"
      diagram = parser.parse(source)

      rel = diagram.relationships.first
      expect(rel.cardinality_from).to eq('one')
      expect(rel.cardinality_to).to eq('zero_or_one')
    end

    it 'parses one-or-more cardinality' do
      source = "erDiagram\nCUSTOMER ||--{| ORDER"
      diagram = parser.parse(source)

      rel = diagram.relationships.first
      expect(rel.cardinality_from).to eq('one')
      expect(rel.cardinality_to).to eq('one_or_more')
    end

    it 'parses relationship without label' do
      source = "erDiagram\nCUSTOMER ||--o{ ORDER"
      diagram = parser.parse(source)

      rel = diagram.relationships.first
      expect(rel.label).to be_nil
    end

    it 'parses multiple entities and relationships' do
      source = <<~MERMAID
        erDiagram
        CUSTOMER ||--o{ ORDER
        ORDER ||--|{ LINE_ITEM
        PRODUCT ||--o{ LINE_ITEM
      MERMAID
      diagram = parser.parse(source)

      expect(diagram.relationships.length).to eq(3)
      # Should have 4 unique entities
      entity_ids = diagram.entities.map(&:id).sort
      expect(entity_ids).to eq(%w[CUSTOMER LINE_ITEM ORDER PRODUCT])
    end

    it 'raises ParseError for invalid syntax' do
      source = 'invalid syntax'
      expect { parser.parse(source) }.to raise_error(
        Sirena::Parser::ParseError
      )
    end
  end

  describe 'style classes' do
    it 'carries the class assigned via ::: (A1)' do
      diagram = parser.parse("erDiagram\nCAR:::someclass")

      expect(diagram.find_entity('CAR').classes).to eq(%w[someclass])
    end

    it 'carries multiple classes in source order (A2)' do
      diagram = parser.parse("erDiagram\nPERSON:::anotherclass,someclass")

      expect(diagram.find_entity('PERSON').classes)
        .to eq(%w[anotherclass someclass])
    end

    it 'records each classDef with its own style text (A3)' do
      source = <<~MERMAID
        erDiagram
        classDef someclass fill:#f96
        classDef anotherclass color:blue
      MERMAID
      diagram = parser.parse(source)

      expect(diagram.class_defs).to eq(
        'someclass' => 'fill:#f96', 'anotherclass' => 'color:blue'
      )
    end

    it 'keeps a class on an entity with an attribute block (A4)' do
      source = "erDiagram\nCAR:::x {\nstring make\n}"
      diagram = parser.parse(source)
      entity = diagram.find_entity('CAR')

      expect(entity.classes).to eq(%w[x])
      expect(entity.attributes.map(&:name)).to eq(%w[make])
    end

    it 'keeps a class on an entity with an empty block (A5)' do
      # An empty block yields a nil :attributes capture. Routing on
      # :entity_id alone (not :entity_id && :attributes) is what keeps
      # this case from losing its class.
      diagram = parser.parse("erDiagram\nCAR:::x {\n}")

      expect(diagram.find_entity('CAR').classes).to eq(%w[x])
    end

    it 'gives an unclassed entity an empty class list (A6)' do
      diagram = parser.parse("erDiagram\nCAR")

      expect(diagram.find_entity('CAR').classes).to eq([])
    end

    it 'keeps classes on both relationship ends (A7)' do
      # Each end captures under a DIFFERENT name (:from_classes,
      # :to_classes). Giving both the same name would drop the from-end
      # class silently when Parslet merges the statement hash.
      source = "erDiagram\nA:::x ||--o{ B:::y : label"
      diagram = parser.parse(source)
      rel = diagram.relationships.first

      expect(diagram.find_entity('A').classes).to eq(%w[x])
      expect(diagram.find_entity('B').classes).to eq(%w[y])
      expect(rel.cardinality_from).to eq('one')
      expect(rel.cardinality_to).to eq('zero_or_more')
    end

    it 'accepts a space after the comma (A8)' do
      diagram = parser.parse("erDiagram\nCAR:::a, b")

      expect(diagram.find_entity('CAR').classes).to eq(%w[a b])
    end

    it 'lets one classDef name several classes (A11)' do
      diagram = parser.parse("erDiagram\nclassDef a, b fill:#f9f")

      expect(diagram.class_defs).to eq('a' => 'fill:#f9f', 'b' => 'fill:#f9f')
    end

    it 'keeps a repeated assignment in source order, not deduped (A12)' do
      # Verified against mermaid's own db: cssClasses is "default a a" for
      # this source, not "default a" — a repeat is NOT collapsed. Whether
      # that matters is a rendering question (a later duplicate can win a
      # conflict); the parser's job is only to keep what was written.
      diagram = parser.parse("erDiagram\nCAR:::a\nCAR:::a")

      expect(diagram.find_entity('CAR').classes).to eq(%w[a a])
    end

    it 'adds rather than replaces on a second entity-path assignment (A13)' do
      source = "erDiagram\nCAR:::a\nCAR:::b {\nstring m\n}"
      diagram = parser.parse(source)

      expect(diagram.find_entity('CAR').classes).to eq(%w[a b])
    end

    it 'adds rather than replaces on the relationship path too (A13b)' do
      source = "erDiagram\nCAR:::a\nCAR:::b ||--o{ X : r"
      diagram = parser.parse(source)

      expect(diagram.find_entity('CAR').classes).to eq(%w[a b])
    end

    it 'does not include a trailing semicolon in the style text (A15)' do
      diagram = parser.parse("erDiagram\nclassDef x fill:#f96;")

      expect(diagram.class_defs).to eq('x' => 'fill:#f96')
    end

    it 'accumulates a repeated classDef for the same name (A16)' do
      # Verified against mermaid's own parser: two classDef statements for
      # one name both survive, in source order — not the last one alone.
      source = "erDiagram\nclassDef a fill:red\nclassDef a stroke:blue"
      diagram = parser.parse(source)

      expect(diagram.class_defs).to eq('a' => 'fill:red,stroke:blue')
    end

    # These six all raise TODAY, so a whole-file revert leaves them green —
    # mutation-check.sh will say STAYED GREEN, correctly. Keep them anyway:
    # each is the set mermaid itself rejects (verified against its own
    # parser, see the plan's harness), and nothing else in this suite
    # notices if the grammar is ever widened past mermaid.
    it 'rejects what mermaid rejects (A14)' do
      fragments = [
        'CAR:::',
        'CAR::x',
        'CAR:::a,',
        'CAR:::1bad',
        'classDef x',
        'CAR:::--'
      ]

      fragments.each do |fragment|
        source = "erDiagram\n#{fragment}"

        expect { parser.parse(source) }.to raise_error(
          Sirena::Parser::ParseError
        )
      end
    end
  end
end
