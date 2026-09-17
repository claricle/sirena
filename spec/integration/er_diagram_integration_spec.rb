# frozen_string_literal: true

require 'spec_helper'
require 'rexml/document'

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

  describe 'classDef styles end to end' do
    let(:engine) { Sirena::Engine.new }

    # The bucket case this branch clears: CAR gets one class (fill only),
    # PERSON gets two (fill and color). This is the oracle split measured
    # from spec/fixtures_mermaid/er/002_platform_yari2_er_1.svg.
    it 'applies per-entity styles from the real corpus case (D1)' do
      source = File.read('spec/mermaid/er/002_platform_yari2_er_1.mmd')
      svg = engine.render(source)
      doc = REXML::Document.new(svg)

      expect(doc.root.name).to eq('svg')

      car = doc.get_elements("//*[@id='entity-CAR']").first
      person = doc.get_elements("//*[@id='entity-PERSON']").first
      expect(car).not_to be_nil
      expect(person).not_to be_nil

      expect(car.get_elements('.//rect').first.attributes['fill'])
        .to eq('#f96')
      expect(person.get_elements('.//rect').first.attributes['fill'])
        .to eq('#f96')

      # `all()` on an empty array passes vacuously whatever the matcher, so
      # each side pins its text COUNT first (name + 3 attributes) and only
      # then asserts every fill. "Stated positively" alone does not close
      # this — an entity rendering zero text nodes would still pass either
      # polarity; only asserting the count does.
      person_text_fills = person.get_elements('.//text')
        .map { |t| t.attributes['fill'] }
      expect(person_text_fills.length).to eq(4)
      expect(person_text_fills).to all(eq('blue'))

      car_text_fills = car.get_elements('.//text')
        .map { |t| t.attributes['fill'] }
      expect(car_text_fills.length).to eq(4)
      expect(car_text_fills).to all(eq('#000000'))
    end

    it 'escapes a hostile style value and preserves it verbatim (D2)' do
      hostile = '"><script>alert(1)</script>'
      source = "erDiagram\nCAR:::a\nclassDef a fill:#{hostile}"

      svg = engine.render(source)

      expect(svg).not_to include('<script')

      doc = REXML::Document.new(svg)
      rect = doc.get_elements("//*[@id='entity-CAR']//rect").first
      expect(rect.attributes['fill']).to eq(hostile)
    end

    it 'keeps an earlier classDef property when a later one adds a new property (D3)' do
      source = <<~MERMAID
        erDiagram
        CAR:::a
        classDef a fill:red
        classDef a stroke:blue
      MERMAID

      svg = engine.render(source)
      doc = REXML::Document.new(svg)
      rect = doc.get_elements("//*[@id='entity-CAR']//rect").first

      expect(rect.attributes['fill']).to eq('red')
      expect(rect.attributes['stroke']).to eq('blue')
    end

    # Verified against mermaid's own db: cssClasses is "default a b a" —
    # the trailing repeat of "a" wins on the conflicting fill.
    it 'lets a repeated class assignment win in source order (D4)' do
      source = <<~MERMAID
        erDiagram
        CAR:::a,b
        CAR:::a
        classDef a fill:red
        classDef b fill:blue
      MERMAID

      svg = engine.render(source)
      doc = REXML::Document.new(svg)
      rect = doc.get_elements("//*[@id='entity-CAR']//rect").first

      expect(rect.attributes['fill']).to eq('red')
    end

    # Verified against mermaid's own db: cssClasses is "default" for an
    # entity with no explicit assignment at all — a declared classDef
    # default applies to it anyway.
    it 'applies a declared classDef default with no explicit assignment (D5)' do
      source = <<~MERMAID
        erDiagram
        CAR
        classDef default fill:red
      MERMAID

      svg = engine.render(source)
      doc = REXML::Document.new(svg)
      rect = doc.get_elements("//*[@id='entity-CAR']//rect").first

      expect(rect.attributes['fill']).to eq('red')
    end

    # Verified against mermaid's own db (stores "FILL:red" verbatim) and a
    # real browser (getComputedStyle resolves it to rgb(255, 0, 0) anyway,
    # since CSS property names are case-insensitive).
    it 'applies a classDef property regardless of its declared case (D6)' do
      source = <<~MERMAID
        erDiagram
        CAR:::a
        classDef a FILL:red
      MERMAID

      svg = engine.render(source)
      doc = REXML::Document.new(svg)
      rect = doc.get_elements("//*[@id='entity-CAR']//rect").first

      expect(rect.attributes['fill']).to eq('red')
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
