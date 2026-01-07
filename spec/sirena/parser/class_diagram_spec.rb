# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::Parser::ClassDiagramParser do
  let(:parser) { described_class.new }

  describe '#parse' do
    it 'parses simple class diagram with two classes' do
      source = "classDiagram\nAnimal <|-- Dog"
      diagram = parser.parse(source)

      expect(diagram).to be_a(Sirena::Diagram::ClassDiagram)
      expect(diagram.entities.length).to eq(2)
      expect(diagram.relationships.length).to eq(1)
    end

    it 'parses inheritance relationship' do
      source = "classDiagram\nAnimal <|-- Dog"
      diagram = parser.parse(source)

      rel = diagram.relationships.first
      expect(rel.from_id).to eq('Dog')
      expect(rel.to_id).to eq('Animal')
      expect(rel.relationship_type).to eq('inheritance')
    end

    it 'parses composition relationship' do
      source = "classDiagram\nCar *-- Engine"
      diagram = parser.parse(source)

      rel = diagram.relationships.first
      expect(rel.relationship_type).to eq('composition')
    end

    it 'parses aggregation relationship' do
      source = "classDiagram\nTeam o-- Player"
      diagram = parser.parse(source)

      rel = diagram.relationships.first
      expect(rel.relationship_type).to eq('aggregation')
    end

    it 'parses association relationship' do
      source = "classDiagram\nStudent -- Course"
      diagram = parser.parse(source)

      rel = diagram.relationships.first
      expect(rel.relationship_type).to eq('association')
    end

    it 'parses class with stereotype' do
      source = <<~MERMAID
        classDiagram
        class Drawable <<interface>>
      MERMAID
      diagram = parser.parse(source)

      entity = diagram.find_entity('Drawable')
      expect(entity).not_to be_nil
      expect(entity.stereotype).to eq('interface')
    end

    it 'parses class with attributes' do
      source = <<~MERMAID
        classDiagram
        class Animal {
          +name: string
          -age: int
        }
      MERMAID
      diagram = parser.parse(source)

      entity = diagram.find_entity('Animal')
      expect(entity.attributes.length).to eq(2)

      attr1 = entity.attributes.first
      expect(attr1.name).to eq('name')
      expect(attr1.type).to eq('string')
      expect(attr1.visibility).to eq('public')

      attr2 = entity.attributes.last
      expect(attr2.name).to eq('age')
      expect(attr2.type).to eq('int')
      expect(attr2.visibility).to eq('private')
    end

    it 'parses class with methods' do
      source = <<~MERMAID
        classDiagram
        class Animal {
          +breathe()
          +move(x: int, y: int): void
        }
      MERMAID
      diagram = parser.parse(source)

      entity = diagram.find_entity('Animal')
      expect(entity.class_methods.length).to eq(2)

      method1 = entity.class_methods.first
      expect(method1.name).to eq('breathe')
      expect(method1.visibility).to eq('public')

      method2 = entity.class_methods.last
      expect(method2.name).to eq('move')
      expect(method2.parameters).to eq('x: int, y: int')
      expect(method2.return_type).to eq('void')
    end

    it 'parses relationship with cardinality' do
      source = "classDiagram\nStudent \"1\" -- \"0..*\" Course"
      diagram = parser.parse(source)

      rel = diagram.relationships.first
      expect(rel.source_cardinality).to eq('1')
      expect(rel.target_cardinality).to eq('0..*')
    end

    it 'parses relationship with label' do
      source = "classDiagram\nStudent -- Course : enrolls in"
      diagram = parser.parse(source)

      rel = diagram.relationships.first
      expect(rel.label).to eq('enrolls in')
    end

    it 'parses relationship with pipe-delimited label' do
      source = "classDiagram\nStudent --|\"enrolls in\"| Course"
      diagram = parser.parse(source)

      rel = diagram.relationships.first
      expect(rel.label).to eq('enrolls in')
    end

    it 'parses relationship with pipe-delimited label using single quotes' do
      source = "classDiagram\nStudent --|'enrolls in'| Course"
      diagram = parser.parse(source)

      rel = diagram.relationships.first
      expect(rel.label).to eq('enrolls in')
    end

    it 'parses arrow relationship with pipe-delimited label' do
      source = "classDiagram\nClassA -->|\"uses\"| ClassB"
      diagram = parser.parse(source)

      rel = diagram.relationships.first
      expect(rel.label).to eq('uses')
      expect(rel.relationship_type).to eq('association')
    end

    it 'parses aggregation with pipe-delimited label' do
      source = "classDiagram\nTeam o--|\"contains\"| Player"
      diagram = parser.parse(source)

      rel = diagram.relationships.first
      expect(rel.label).to eq('contains')
      expect(rel.relationship_type).to eq('aggregation')
    end

    it 'parses composition with pipe-delimited label' do
      source = "classDiagram\nCar *--|\"has\"| Engine"
      diagram = parser.parse(source)

      rel = diagram.relationships.first
      expect(rel.label).to eq('has')
      expect(rel.relationship_type).to eq('composition')
    end

    it 'parses relationship with cardinality and pipe-delimited label' do
      source = "classDiagram\nStudent \"1\" --|\"enrolls in\"| \"0..*\" Course"
      diagram = parser.parse(source)

      rel = diagram.relationships.first
      expect(rel.source_cardinality).to eq('1')
      expect(rel.target_cardinality).to eq('0..*')
      expect(rel.label).to eq('enrolls in')
    end

    it 'parses class diagram with direction' do
      source = "classDiagram TB\nAnimal <|-- Dog"
      diagram = parser.parse(source)

      expect(diagram.direction).to eq('TB')
    end

    it 'raises ParseError for invalid syntax' do
      source = 'invalid syntax'
      expect { parser.parse(source) }.to raise_error(
        Sirena::Parser::ParseError
      )
    end
  end
end
