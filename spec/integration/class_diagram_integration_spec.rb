# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'ClassDiagram Integration' do
  describe 'complete class diagram pipeline' do
    let(:parser) { Sirena::Parser::ClassDiagramParser.new }
    let(:transform) { Sirena::Transform::ClassDiagramTransform.new }
    let(:renderer) { Sirena::Renderer::ClassDiagramRenderer.new }

    it 'parses, transforms, and renders a simple class diagram' do
      source = "classDiagram\nAnimal <|-- Dog"

      # Parse
      diagram = parser.parse(source)
      expect(diagram).to be_a(Sirena::Diagram::ClassDiagram)
      expect(diagram.valid?).to be true

      # Transform
      graph = transform.to_graph(diagram)
      expect(graph).to be_a(Hash)
      expect(graph[:children].length).to eq(2)
      expect(graph[:edges].length).to eq(1)

      # Render (without elkrb layout, just with graph structure)
      svg = renderer.render(graph)
      expect(svg).to be_a(Sirena::Svg::Document)
      expect(svg.children).not_to be_empty
    end

    it 'handles multiple relationship types' do
      source = <<~MERMAID
        classDiagram
        Animal <|-- Dog
        Car *-- Engine
        Team o-- Player
        Student -- Course
      MERMAID

      diagram = parser.parse(source)

      expect(diagram.entities.length).to eq(8)
      expect(diagram.relationships.length).to eq(4)
      expect(diagram.inheritance_relationships.length).to eq(1)
      expect(diagram.composition_relationships.length).to eq(1)
      expect(diagram.aggregation_relationships.length).to eq(1)

      graph = transform.to_graph(diagram)
      svg = renderer.render(graph)

      expect(svg).to be_a(Sirena::Svg::Document)
    end

    it 'handles classes with attributes and methods' do
      source = <<~MERMAID
        classDiagram
        class Animal {
          +name: string
          #age: int
          +breathe()
          +move(x: int, y: int): void
        }
        class Dog {
          +bark(): void
        }
        Animal <|-- Dog
      MERMAID

      diagram = parser.parse(source)

      animal = diagram.find_entity('Animal')
      expect(animal).not_to be_nil
      expect(animal.attributes.length).to eq(2)
      expect(animal.class_methods.length).to eq(2)

      dog = diagram.find_entity('Dog')
      expect(dog).not_to be_nil
      expect(dog.class_methods.length).to eq(1)

      graph = transform.to_graph(diagram)
      svg = renderer.render(graph)

      expect(svg).to be_a(Sirena::Svg::Document)
    end

    it 'handles stereotypes' do
      source = <<~MERMAID
        classDiagram
        class Drawable <<interface>> {
          +draw(): void
        }
        class Shape <<abstract>> {
          +area(): float
        }
        Drawable <|-- Shape
      MERMAID

      diagram = parser.parse(source)

      drawable = diagram.find_entity('Drawable')
      expect(drawable.interface?).to be true

      shape = diagram.find_entity('Shape')
      expect(shape.abstract?).to be true

      graph = transform.to_graph(diagram)
      svg = renderer.render(graph)

      expect(svg).to be_a(Sirena::Svg::Document)
    end

    it 'handles different directions' do
      source = "classDiagram LR\nAnimal <|-- Dog"

      diagram = parser.parse(source)
      expect(diagram.direction).to eq('LR')

      graph = transform.to_graph(diagram)
      expect(graph[:layoutOptions]['elk.direction']).to eq('RIGHT')
    end

    it 'handles cardinality labels' do
      source = "classDiagram\nStudent \"1\" -- \"0..*\" Course : enrolls in"

      diagram = parser.parse(source)

      rel = diagram.relationships.first
      expect(rel.source_cardinality).to eq('1')
      expect(rel.target_cardinality).to eq('0..*')
      expect(rel.label).to eq('enrolls in')

      graph = transform.to_graph(diagram)
      edge = graph[:edges].first
      expect(edge[:labels].length).to be > 0
    end
  end

  describe 'DiagramRegistry integration' do
    it 'has class_diagram registered' do
      expect(Sirena::DiagramRegistry.registered?(:class_diagram)).to be true
    end

    it 'retrieves class diagram handlers' do
      handlers = Sirena::DiagramRegistry.get(:class_diagram)

      expect(handlers).not_to be_nil
      expect(handlers[:parser]).to eq(
        Sirena::Parser::ClassDiagramParser
      )
      expect(handlers[:transform]).to eq(
        Sirena::Transform::ClassDiagramTransform
      )
      expect(handlers[:renderer]).to eq(
        Sirena::Renderer::ClassDiagramRenderer
      )
    end
  end
end
