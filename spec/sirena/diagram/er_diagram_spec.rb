# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::Diagram::ErDiagram do
  describe '#diagram_type' do
    it 'returns :er_diagram' do
      diagram = described_class.new
      expect(diagram.diagram_type).to eq(:er_diagram)
    end
  end

  describe '#valid?' do
    it 'returns true for valid diagram with entities' do
      diagram = described_class.new
      diagram.entities << Sirena::Diagram::ErEntity.new(
        id: 'CUSTOMER',
        name: 'CUSTOMER'
      )

      expect(diagram.valid?).to be true
    end

    it 'returns false for diagram without entities' do
      diagram = described_class.new
      expect(diagram.valid?).to be false
    end

    it 'returns false when relationship references non-existent entity' do
      diagram = described_class.new
      diagram.entities << Sirena::Diagram::ErEntity.new(
        id: 'CUSTOMER',
        name: 'CUSTOMER'
      )
      diagram.relationships << Sirena::Diagram::ErRelationship.new(
        from_id: 'CUSTOMER',
        to_id: 'ORDER',
        relationship_type: 'non-identifying',
        cardinality_from: 'one',
        cardinality_to: 'zero_or_more'
      )

      expect(diagram.valid?).to be false
    end
  end

  describe '#find_entity' do
    let(:diagram) { described_class.new }
    let(:entity) do
      Sirena::Diagram::ErEntity.new(
        id: 'CUSTOMER',
        name: 'CUSTOMER'
      )
    end

    before { diagram.entities << entity }

    it 'finds entity by id' do
      expect(diagram.find_entity('CUSTOMER')).to eq(entity)
    end

    it 'returns nil for non-existent id' do
      expect(diagram.find_entity('UNKNOWN')).to be_nil
    end
  end

  describe '#relationships_from' do
    let(:diagram) { described_class.new }
    let(:relationship) do
      Sirena::Diagram::ErRelationship.new(
        from_id: 'CUSTOMER',
        to_id: 'ORDER',
        relationship_type: 'non-identifying',
        cardinality_from: 'one',
        cardinality_to: 'zero_or_more'
      )
    end

    before { diagram.relationships << relationship }

    it 'finds relationships originating from entity' do
      expect(diagram.relationships_from('CUSTOMER')).to eq([relationship])
    end

    it 'returns empty array for entity with no outgoing relationships' do
      expect(diagram.relationships_from('ORDER')).to eq([])
    end
  end

  describe '#identifying_relationships' do
    let(:diagram) { described_class.new }

    it 'returns only identifying relationships' do
      diagram.relationships << Sirena::Diagram::ErRelationship.new(
        from_id: 'CUSTOMER',
        to_id: 'ORDER',
        relationship_type: 'identifying',
        cardinality_from: 'one',
        cardinality_to: 'zero_or_more'
      )
      diagram.relationships << Sirena::Diagram::ErRelationship.new(
        from_id: 'ORDER',
        to_id: 'PRODUCT',
        relationship_type: 'non-identifying',
        cardinality_from: 'one',
        cardinality_to: 'one_or_more'
      )

      expect(diagram.identifying_relationships.length).to eq(1)
      expect(diagram.identifying_relationships.first.relationship_type).to eq(
        'identifying'
      )
    end
  end
end

RSpec.describe Sirena::Diagram::ErEntity do
  describe '#valid?' do
    it 'returns true for entity with id and name' do
      entity = described_class.new(id: 'CUSTOMER', name: 'CUSTOMER')
      expect(entity.valid?).to be true
    end

    it 'returns false for entity without id' do
      entity = described_class.new(name: 'CUSTOMER')
      expect(entity.valid?).to be false
    end

    it 'returns false for entity without name' do
      entity = described_class.new(id: 'CUSTOMER')
      expect(entity.valid?).to be false
    end
  end
end

RSpec.describe Sirena::Diagram::ErAttribute do
  describe '#valid?' do
    it 'returns true for attribute with name' do
      attribute = described_class.new(name: 'customer_id')
      expect(attribute.valid?).to be true
    end

    it 'returns false for attribute without name' do
      attribute = described_class.new
      expect(attribute.valid?).to be false
    end
  end

  describe '#primary_key?' do
    it 'returns true when key_type is PK' do
      attribute = described_class.new(
        name: 'id',
        key_type: 'PK'
      )
      expect(attribute.primary_key?).to be true
    end

    it 'returns false when key_type is not PK' do
      attribute = described_class.new(name: 'name')
      expect(attribute.primary_key?).to be false
    end
  end

  describe '#foreign_key?' do
    it 'returns true when key_type is FK' do
      attribute = described_class.new(
        name: 'customer_id',
        key_type: 'FK'
      )
      expect(attribute.foreign_key?).to be true
    end

    it 'returns false when key_type is not FK' do
      attribute = described_class.new(name: 'name')
      expect(attribute.foreign_key?).to be false
    end
  end
end

RSpec.describe Sirena::Diagram::ErRelationship do
  describe '#valid?' do
    it 'returns true for relationship with all required fields' do
      relationship = described_class.new(
        from_id: 'CUSTOMER',
        to_id: 'ORDER',
        relationship_type: 'non-identifying',
        cardinality_from: 'one',
        cardinality_to: 'zero_or_more'
      )
      expect(relationship.valid?).to be true
    end

    it 'returns false without from_id' do
      relationship = described_class.new(
        to_id: 'ORDER',
        relationship_type: 'non-identifying',
        cardinality_from: 'one',
        cardinality_to: 'zero_or_more'
      )
      expect(relationship.valid?).to be false
    end

    it 'returns false without cardinality_from' do
      relationship = described_class.new(
        from_id: 'CUSTOMER',
        to_id: 'ORDER',
        relationship_type: 'non-identifying',
        cardinality_to: 'zero_or_more'
      )
      expect(relationship.valid?).to be false
    end
  end

  describe '#identifying?' do
    it 'returns true for identifying type' do
      relationship = described_class.new(
        from_id: 'CUSTOMER',
        to_id: 'ORDER',
        relationship_type: 'identifying',
        cardinality_from: 'one',
        cardinality_to: 'zero_or_more'
      )
      expect(relationship.identifying?).to be true
    end

    it 'returns false for other types' do
      relationship = described_class.new(
        from_id: 'CUSTOMER',
        to_id: 'ORDER',
        relationship_type: 'non-identifying',
        cardinality_from: 'one',
        cardinality_to: 'zero_or_more'
      )
      expect(relationship.identifying?).to be false
    end
  end

  describe '#non_identifying?' do
    it 'returns true for non-identifying type' do
      relationship = described_class.new(
        from_id: 'CUSTOMER',
        to_id: 'ORDER',
        relationship_type: 'non-identifying',
        cardinality_from: 'one',
        cardinality_to: 'zero_or_more'
      )
      expect(relationship.non_identifying?).to be true
    end
  end
end
