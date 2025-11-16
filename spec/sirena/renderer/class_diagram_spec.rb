# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::Renderer::ClassDiagramRenderer do
  let(:renderer) { described_class.new }

  describe '#render' do
    let(:graph) do
      {
        id: 'class_diagram',
        children: [
          {
            id: 'Animal',
            x: 10,
            y: 10,
            width: 150,
            height: 100,
            labels: [{ text: 'Animal', width: 60, height: 16 }],
            metadata: {
              name: 'Animal',
              stereotype: nil,
              attributes: [
                { name: 'age', type: 'int', visibility: 'protected' }
              ],
              methods: [
                { name: 'breathe', parameters: nil, return_type: nil,
                  visibility: 'public' }
              ]
            }
          },
          {
            id: 'Dog',
            x: 200,
            y: 10,
            width: 150,
            height: 80,
            labels: [{ text: 'Dog', width: 40, height: 16 }],
            metadata: {
              name: 'Dog',
              stereotype: nil,
              attributes: [],
              methods: [
                { name: 'bark', parameters: nil, return_type: nil,
                  visibility: 'public' }
              ]
            }
          }
        ],
        edges: [
          {
            id: 'Dog_to_Animal',
            sources: ['Dog'],
            targets: ['Animal'],
            metadata: { relationship_type: 'inheritance' }
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

    it 'includes class boxes in SVG' do
      svg = renderer.render(graph)

      groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group)
      end
      expect(groups.length).to be > 0
    end

    it 'renders class boxes as rectangles' do
      svg = renderer.render(graph)

      groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group)
      end

      rects = groups.flat_map(&:children).select do |c|
        c.is_a?(Sirena::Svg::Rect)
      end

      expect(rects).not_to be_empty
    end

    it 'renders class names as text elements' do
      svg = renderer.render(graph)

      groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group)
      end

      texts = groups.flat_map(&:children).select do |c|
        c.is_a?(Sirena::Svg::Text)
      end

      expect(texts).not_to be_empty
      class_names = texts.map(&:content)
      expect(class_names).to include('Animal')
    end

    it 'renders attributes with visibility symbols' do
      svg = renderer.render(graph)

      groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group)
      end

      texts = groups.flat_map(&:children).select do |c|
        c.is_a?(Sirena::Svg::Text)
      end

      attr_texts = texts.map(&:content).grep(/age/)
      expect(attr_texts).not_to be_empty
      expect(attr_texts.first).to include('#')
    end

    it 'renders methods with visibility symbols' do
      svg = renderer.render(graph)

      groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group)
      end

      texts = groups.flat_map(&:children).select do |c|
        c.is_a?(Sirena::Svg::Text)
      end

      method_texts = texts.map(&:content).grep(/breathe|bark/)
      expect(method_texts).not_to be_empty
      expect(method_texts.first).to include('+')
    end

    it 'renders compartment separators' do
      svg = renderer.render(graph)

      groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group)
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
    end

    it 'renders stereotypes when present' do
      graph[:children][0][:metadata][:stereotype] = 'interface'
      svg = renderer.render(graph)

      groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group)
      end

      texts = groups.flat_map(&:children).select do |c|
        c.is_a?(Sirena::Svg::Text)
      end

      stereotype_texts = texts.map(&:content).grep(/<<.*>>/)
      expect(stereotype_texts).not_to be_empty
      expect(stereotype_texts.first).to include('interface')
    end
  end
end
