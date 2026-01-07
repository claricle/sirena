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

      rects = groups.flat_map(&:children).select do |c|
        c.is_a?(Sirena::Svg::Rect)
      end

      expect(rects).not_to be_empty
      expect(rects.length).to be >= 2
    end

    it 'renders entity names as text elements' do
      svg = renderer.render(graph)

      groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group) && c.id&.start_with?('entity-')
      end

      texts = groups.flat_map(&:children).select do |c|
        c.is_a?(Sirena::Svg::Text)
      end

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

      texts = groups.flat_map(&:children).select do |c|
        c.is_a?(Sirena::Svg::Text)
      end

      attr_texts = texts.map(&:content).grep(/PK|FK/)
      expect(attr_texts).not_to be_empty
      expect(attr_texts.any? { |t| t.include?('PK') }).to be true
    end

    it 'renders entity separators' do
      svg = renderer.render(graph)

      groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group) && c.id&.start_with?('entity-')
      end

      lines = groups.flat_map(&:children).select do |c|
        c.is_a?(Sirena::Svg::Line)
      end

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

      lines = rel_groups.flat_map(&:children).select do |c|
        c.is_a?(Sirena::Svg::Line)
      end

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

      texts = rel_groups.flat_map(&:children).select do |c|
        c.is_a?(Sirena::Svg::Text)
      end

      label_texts = texts.map(&:content)
      expect(label_texts).to include('places')
    end
  end
end
