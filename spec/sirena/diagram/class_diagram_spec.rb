# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::Diagram::ClassDiagram do
  describe '#diagram_type' do
    it 'returns :class_diagram' do
      diagram = described_class.new
      expect(diagram.diagram_type).to eq(:class_diagram)
    end
  end

  describe '#valid?' do
    it 'returns true for valid diagram with entities' do
      diagram = described_class.new(direction: 'TB')
      diagram.entities << Sirena::Diagram::ClassEntity.new(
        id: 'Animal',
        name: 'Animal'
      )

      expect(diagram.valid?).to be true
    end

    it 'returns false for diagram without entities' do
      diagram = described_class.new(direction: 'TB')
      expect(diagram.valid?).to be false
    end

    it 'returns false when relationship references non-existent entity' do
      diagram = described_class.new(direction: 'TB')
      diagram.entities << Sirena::Diagram::ClassEntity.new(
        id: 'Dog',
        name: 'Dog'
      )
      diagram.relationships << Sirena::Diagram::ClassRelationship.new(
        from_id: 'Dog',
        to_id: 'Animal',
        relationship_type: 'inheritance'
      )

      expect(diagram.valid?).to be false
    end
  end

  describe '#find_entity' do
    let(:diagram) { described_class.new }
    let(:entity) do
      Sirena::Diagram::ClassEntity.new(
        id: 'Animal',
        name: 'Animal'
      )
    end

    before { diagram.entities << entity }

    it 'finds entity by id' do
      expect(diagram.find_entity('Animal')).to eq(entity)
    end

    it 'returns nil for non-existent id' do
      expect(diagram.find_entity('Unknown')).to be_nil
    end
  end

  describe '#relationships_from' do
    let(:diagram) { described_class.new }
    let(:relationship) do
      Sirena::Diagram::ClassRelationship.new(
        from_id: 'Dog',
        to_id: 'Animal',
        relationship_type: 'inheritance'
      )
    end

    before { diagram.relationships << relationship }

    it 'finds relationships originating from entity' do
      expect(diagram.relationships_from('Dog')).to eq([relationship])
    end

    it 'returns empty array for entity with no outgoing relationships' do
      expect(diagram.relationships_from('Animal')).to eq([])
    end
  end

  describe '#inheritance_relationships' do
    let(:diagram) { described_class.new }

    it 'returns only inheritance relationships' do
      diagram.relationships << Sirena::Diagram::ClassRelationship.new(
        from_id: 'Dog',
        to_id: 'Animal',
        relationship_type: 'inheritance'
      )
      diagram.relationships << Sirena::Diagram::ClassRelationship.new(
        from_id: 'Car',
        to_id: 'Engine',
        relationship_type: 'composition'
      )

      expect(diagram.inheritance_relationships.length).to eq(1)
      expect(diagram.inheritance_relationships.first.relationship_type).to eq(
        'inheritance'
      )
    end
  end
end

RSpec.describe Sirena::Diagram::ClassEntity do
  describe '#valid?' do
    it 'returns true for entity with id and name' do
      entity = described_class.new(id: 'Dog', name: 'Dog')
      expect(entity.valid?).to be true
    end

    it 'returns false for entity without id' do
      entity = described_class.new(name: 'Dog')
      expect(entity.valid?).to be false
    end

    it 'returns false for entity without name' do
      entity = described_class.new(id: 'Dog')
      expect(entity.valid?).to be false
    end
  end

  describe '#interface?' do
    it 'returns true when stereotype is interface' do
      entity = described_class.new(
        id: 'Drawable',
        name: 'Drawable',
        stereotype: 'interface'
      )
      expect(entity.interface?).to be true
    end

    it 'returns false when stereotype is not interface' do
      entity = described_class.new(id: 'Dog', name: 'Dog')
      expect(entity.interface?).to be false
    end
  end

  describe '#abstract?' do
    it 'returns true when stereotype is abstract' do
      entity = described_class.new(
        id: 'Animal',
        name: 'Animal',
        stereotype: 'abstract'
      )
      expect(entity.abstract?).to be true
    end
  end
end

RSpec.describe Sirena::Diagram::ClassAttribute do
  describe '#valid?' do
    it 'returns true for attribute with name' do
      attribute = described_class.new(name: 'age')
      expect(attribute.valid?).to be true
    end

    it 'returns false for attribute without name' do
      attribute = described_class.new
      expect(attribute.valid?).to be false
    end
  end

  describe '#visibility_symbol' do
    it 'returns + for public visibility' do
      attribute = described_class.new(name: 'name', visibility: 'public')
      expect(attribute.visibility_symbol).to eq('+')
    end

    it 'returns - for private visibility' do
      attribute = described_class.new(name: 'secret', visibility: 'private')
      expect(attribute.visibility_symbol).to eq('-')
    end

    it 'returns # for protected visibility' do
      attribute = described_class.new(name: 'data', visibility: 'protected')
      expect(attribute.visibility_symbol).to eq('#')
    end

    it 'returns ~ for package visibility' do
      attribute = described_class.new(name: 'internal', visibility: 'package')
      expect(attribute.visibility_symbol).to eq('~')
    end
  end
end

RSpec.describe Sirena::Diagram::ClassMethod do
  describe '#valid?' do
    it 'returns true for method with name' do
      method = described_class.new(name: 'bark')
      expect(method.valid?).to be true
    end

    it 'returns false for method without name' do
      method = described_class.new
      expect(method.valid?).to be false
    end
  end

  describe '#signature' do
    it 'returns method name for simple method' do
      method = described_class.new(name: 'bark')
      expect(method.signature).to eq('bark')
    end

    it 'includes parameters when present' do
      method = described_class.new(name: 'move', parameters: 'x: int, y: int')
      expect(method.signature).to eq('move(x: int, y: int)')
    end

    it 'includes return type when present' do
      method = described_class.new(name: 'getName', return_type: 'String')
      expect(method.signature).to eq('getName String')
    end

    it 'includes both parameters and return type' do
      method = described_class.new(
        name: 'add',
        parameters: 'a: int, b: int',
        return_type: 'int'
      )
      expect(method.signature).to eq('add(a: int, b: int) int')
    end
  end
end

RSpec.describe Sirena::Diagram::ClassRelationship do
  describe '#valid?' do
    it 'returns true for relationship with from and to ids' do
      relationship = described_class.new(
        from_id: 'Dog',
        to_id: 'Animal',
        relationship_type: 'inheritance'
      )
      expect(relationship.valid?).to be true
    end

    it 'returns false without from_id' do
      relationship = described_class.new(
        to_id: 'Animal',
        relationship_type: 'inheritance'
      )
      expect(relationship.valid?).to be false
    end

    it 'returns false without to_id' do
      relationship = described_class.new(
        from_id: 'Dog',
        relationship_type: 'inheritance'
      )
      expect(relationship.valid?).to be false
    end
  end

  describe '#inheritance?' do
    it 'returns true for inheritance type' do
      relationship = described_class.new(
        from_id: 'Dog',
        to_id: 'Animal',
        relationship_type: 'inheritance'
      )
      expect(relationship.inheritance?).to be true
    end

    it 'returns false for other types' do
      relationship = described_class.new(
        from_id: 'Car',
        to_id: 'Engine',
        relationship_type: 'composition'
      )
      expect(relationship.inheritance?).to be false
    end
  end

  describe '#composition?' do
    it 'returns true for composition type' do
      relationship = described_class.new(
        from_id: 'Car',
        to_id: 'Engine',
        relationship_type: 'composition'
      )
      expect(relationship.composition?).to be true
    end
  end

  describe '#aggregation?' do
    it 'returns true for aggregation type' do
      relationship = described_class.new(
        from_id: 'Team',
        to_id: 'Player',
        relationship_type: 'aggregation'
      )
      expect(relationship.aggregation?).to be true
    end
  end
end
