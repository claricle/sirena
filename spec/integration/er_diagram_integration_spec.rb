# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'ErDiagram Integration' do
  describe 'complete ER diagram pipeline' do
    let(:parser) { Sirena::Parser::ErDiagramParser.new }
    let(:transform) { Sirena::Transform::ErDiagramTransform.new }
    let(:renderer) { Sirena::Renderer::ErDiagramRenderer.new }

    it 'parses, transforms, and renders a simple ER diagram' do
      source = "erDiagram\nCUSTOMER ||--o{ ORDER"

      # Parse
      diagram = parser.parse(source)
      expect(diagram).to be_a(Sirena::Diagram::ErDiagram)
      expect(diagram.valid?).to be true

      # Transform
      graph = transform.to_graph(diagram)
      expect(graph).to be_a(Hash)
      expect(graph[:children].length).to eq(2)
      expect(graph[:edges].length).to eq(1)

      # Render
      svg = renderer.render(graph)
      expect(svg).to be_a(Sirena::Svg::Document)
      expect(svg.children).not_to be_empty
    end

    it 'handles entity definitions with attributes' do
      source = <<~MERMAID
        erDiagram
        CUSTOMER {
          int id PK
          string name
          string email
        }
        ORDER {
          int order_id PK
          int customer_id FK
          date order_date
        }
        CUSTOMER ||--o{ ORDER
      MERMAID

      diagram = parser.parse(source)

      customer = diagram.find_entity('CUSTOMER')
      expect(customer).not_to be_nil
      expect(customer.attributes.length).to eq(3)
      expect(customer.attributes.first.primary_key?).to be true

      order = diagram.find_entity('ORDER')
      expect(order).not_to be_nil
      expect(order.attributes.length).to eq(3)
      expect(order.attributes[1].foreign_key?).to be true

      graph = transform.to_graph(diagram)
      svg = renderer.render(graph)

      expect(svg).to be_a(Sirena::Svg::Document)
    end

    it 'handles multiple relationships with different cardinalities' do
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

      rel1 = diagram.relationships[0]
      expect(rel1.cardinality_from).to eq('one')
      expect(rel1.cardinality_to).to eq('zero_or_more')

      rel2 = diagram.relationships[1]
      expect(rel2.cardinality_from).to eq('one')
      expect(rel2.cardinality_to).to eq('one_or_more')

      graph = transform.to_graph(diagram)
      svg = renderer.render(graph)

      expect(svg).to be_a(Sirena::Svg::Document)
    end

    it 'handles identifying relationships' do
      source = "erDiagram\nCUSTOMER ||==o{ ORDER"

      diagram = parser.parse(source)

      rel = diagram.relationships.first
      expect(rel.identifying?).to be true

      graph = transform.to_graph(diagram)
      svg = renderer.render(graph)

      expect(svg).to be_a(Sirena::Svg::Document)
    end

    it 'handles relationships without labels' do
      source = "erDiagram\nCUSTOMER ||--o{ ORDER"

      diagram = parser.parse(source)

      rel = diagram.relationships.first
      expect(rel.label).to be_nil

      graph = transform.to_graph(diagram)
      svg = renderer.render(graph)

      expect(svg).to be_a(Sirena::Svg::Document)
    end

    it 'handles zero-or-one cardinality' do
      source = "erDiagram\nCUSTOMER ||--}o ADDRESS"

      diagram = parser.parse(source)

      rel = diagram.relationships.first
      expect(rel.cardinality_from).to eq('one')
      expect(rel.cardinality_to).to eq('zero_or_one')

      graph = transform.to_graph(diagram)
      svg = renderer.render(graph)

      expect(svg).to be_a(Sirena::Svg::Document)
    end
  end

  describe 'DiagramRegistry integration' do
    it 'has er_diagram registered' do
      expect(Sirena::DiagramRegistry.registered?(:er_diagram)).to be true
    end

    it 'retrieves ER diagram handlers' do
      handlers = Sirena::DiagramRegistry.get(:er_diagram)

      expect(handlers).not_to be_nil
      expect(handlers[:parser]).to eq(
        Sirena::Parser::ErDiagramParser
      )
      expect(handlers[:transform]).to eq(
        Sirena::Transform::ErDiagramTransform
      )
      expect(handlers[:renderer]).to eq(
        Sirena::Renderer::ErDiagramRenderer
      )
    end
  end
end
