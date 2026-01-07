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
end
