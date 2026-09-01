# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::Renderer::ErDiagramRenderer do
  let(:renderer) { described_class.new }

  describe '#render' do
    let(:graph) do
      {
        id: 'er_diagram',
        children: [
          {
            id: 'CUSTOMER',
            x: 10,
            y: 10,
            width: 180,
            height: 120,
            labels: [{ text: 'CUSTOMER', width: 80, height: 16 }],
            metadata: {
              name: 'CUSTOMER',
              attributes: [
                { name: 'id', attribute_type: 'int', key_type: 'PK' },
                { name: 'name', attribute_type: 'string', key_type: nil }
              ]
            }
          },
          {
            id: 'ORDER',
            x: 250,
            y: 10,
            width: 180,
            height: 100,
            labels: [{ text: 'ORDER', width: 60, height: 16 }],
            metadata: {
              name: 'ORDER',
              attributes: [
                { name: 'order_id', attribute_type: 'int', key_type: 'PK' }
              ]
            }
          }
        ],
        edges: [
          {
            id: 'CUSTOMER_to_ORDER',
            sources: ['CUSTOMER'],
            targets: ['ORDER'],
            labels: [{ text: 'places' }],
            metadata: {
              relationship_type: 'non-identifying',
              cardinality_from: 'one',
              cardinality_to: 'zero_or_more'
            }
          }
        ]
      }
    end

    it 'renders graph to SVG document' do
      svg = renderer.render(graph)

      expect(svg).to be_a(Sirena::Svg::Document)
      expect(svg.width).to be > 0
      expect(svg.height).to be > 0
    end

    it 'includes entity boxes in SVG' do
      svg = renderer.render(graph)

      groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group) && c.id&.start_with?('entity-')
      end
      expect(groups.length).to eq(2)
    end

    it 'renders entity boxes as rectangles' do
      svg = renderer.render(graph)

      groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group) && c.id&.start_with?('entity-')
      end

      rects = groups.flat_map(&:children).grep(Sirena::Svg::Rect)

      expect(rects).not_to be_empty
      expect(rects.length).to be >= 2
    end

    it 'renders entity names as text elements' do
      svg = renderer.render(graph)

      groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group) && c.id&.start_with?('entity-')
      end

      texts = groups.flat_map(&:children).grep(Sirena::Svg::Text)

      expect(texts).not_to be_empty
      entity_names = texts.map(&:content)
      expect(entity_names).to include('CUSTOMER')
      expect(entity_names).to include('ORDER')
    end

    it 'renders attributes with key type markers' do
      svg = renderer.render(graph)

      groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group) && c.id&.start_with?('entity-')
      end

      texts = groups.flat_map(&:children).grep(Sirena::Svg::Text)

      attr_texts = texts.map(&:content).grep(/PK|FK/)
      expect(attr_texts).not_to be_empty
      expect(attr_texts.any? { |t| t.include?('PK') }).to be true
    end

    it 'renders entity separators' do
      svg = renderer.render(graph)

      groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group) && c.id&.start_with?('entity-')
      end

      lines = groups.flat_map(&:children).grep(Sirena::Svg::Line)

      expect(lines).not_to be_empty
    end

    it 'renders relationships' do
      svg = renderer.render(graph)

      groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group) && c.id&.start_with?('rel-')
      end

      expect(groups).not_to be_empty
      expect(groups.length).to eq(1)
    end

    it 'renders relationship lines' do
      svg = renderer.render(graph)

      rel_groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group) && c.id&.start_with?('rel-')
      end

      lines = rel_groups.flat_map(&:children).grep(Sirena::Svg::Line)

      expect(lines).not_to be_empty
    end

    it 'renders cardinality markers' do
      svg = renderer.render(graph)

      rel_groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group) && c.id&.start_with?('rel-')
      end

      # Check for circles (zero marker) and lines (cardinality markers)
      elements = rel_groups.flat_map(&:children)
      has_cardinality = elements.any? do |e|
        e.is_a?(Sirena::Svg::Circle) || e.is_a?(Sirena::Svg::Line)
      end

      expect(has_cardinality).to be true
    end

    it 'renders relationship labels' do
      svg = renderer.render(graph)

      rel_groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group) && c.id&.start_with?('rel-')
      end

      texts = rel_groups.flat_map(&:children).grep(Sirena::Svg::Text)

      label_texts = texts.map(&:content)
      expect(label_texts).to include('places')
    end

    context 'with a graph that has no entities and no relationships' do
      let(:empty_graph) { { id: 'er_diagram', children: [], edges: [] } }

      # Size and emptiness are one property: what an empty ER diagram looks
      # like. Asserting emptiness on its own proved nothing — an empty graph
      # already drew no children on the old 880x680 canvas.
      #
      # The EXTENT is mermaid's; the origin is not. mmdc emits
      # viewBox="-8 -8 16 16" for this source, from centring a zero-size
      # bounding box. Sirena keeps the "0 0" origin every one of its other
      # diagrams uses, so only 16x16 is the parity claim being made here.
      it 'matches the 16x16 extent mermaid gives an empty ER diagram' do
        svg = renderer.render(empty_graph)

        expect(svg.width).to eq(16)
        expect(svg.height).to eq(16)
        expect(svg.view_box).to eq('0 0 16 16')
        expect(svg.children).to eq([])
      end
    end

    context 'with entities but no relationships' do
      let(:entity_only_graph) do
        { id: 'er_diagram', children: [graph[:children].first], edges: [] }
      end

      # The empty-canvas gate is a conjunction, and this is the corner that
      # pins the `&&`. WITHOUT this example, flipping it to `||` left the whole
      # suite green while every relationship-free ER diagram — the most
      # ordinary kind there is — collapsed to the 16x16 stub and lost its
      # entities. This example is what now fails under that mutation.
      it 'draws the entities at content size, not the empty canvas' do
        svg = renderer.render(entity_only_graph)

        expect(svg.width).to eq(270)
        expect(svg.height).to eq(210)
        expect(svg.children.map(&:id)).to eq(['entity-CUSTOMER'])
      end
    end

    context 'with a graph whose collection keys are absent' do
      it 'keeps the no-content defaults rather than the empty canvas' do
        svg = renderer.render({ id: 'er_diagram' })

        expect(svg.width).to eq(840)
        expect(svg.height).to eq(640)
      end
    end
  end
end
