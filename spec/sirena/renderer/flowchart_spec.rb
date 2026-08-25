# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::Renderer::FlowchartRenderer do
  let(:renderer) { described_class.new }

  describe '#render' do
    let(:graph) do
      {
        id: 'flowchart',
        children: [
          {
            id: 'A',
            x: 10,
            y: 10,
            width: 100,
            height: 50,
            labels: [{ text: 'Start', width: 50, height: 14 }],
            metadata: { shape: 'rect' }
          },
          {
            id: 'B',
            x: 150,
            y: 10,
            width: 100,
            height: 50,
            labels: [{ text: 'End', width: 35, height: 14 }],
            metadata: { shape: 'rect' }
          }
        ],
        edges: [
          {
            id: 'A_to_B',
            sources: ['A'],
            targets: ['B'],
            metadata: { arrow_type: 'arrow' }
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

    it 'includes nodes in SVG' do
      svg = renderer.render(graph)

      # Should have groups for nodes
      groups = svg.children.grep(Sirena::Svg::Group)
      expect(groups.length).to be > 0
    end

    it 'renders rectangle nodes' do
      svg = renderer.render(graph)

      # Find groups and check for rect children
      groups = svg.children.grep(Sirena::Svg::Group)

      rects = groups.flat_map(&:children).grep(Sirena::Svg::Rect)

      expect(rects).not_to be_empty
    end

    it 'renders circle nodes' do
      graph[:children][0][:metadata][:shape] = 'circle'

      svg = renderer.render(graph)

      groups = svg.children.grep(Sirena::Svg::Group)

      circles = groups.flat_map(&:children).grep(Sirena::Svg::Circle)

      expect(circles).not_to be_empty
    end

    it 'renders node labels as text elements' do
      svg = renderer.render(graph)

      groups = svg.children.grep(Sirena::Svg::Group)

      texts = groups.flat_map(&:children).grep(Sirena::Svg::Text)

      expect(texts).not_to be_empty
      expect(texts.first.content).to eq('Start')
    end

    it 'renders edges as paths' do
      svg = renderer.render(graph)

      groups = svg.children.grep(Sirena::Svg::Group)

      paths = groups.flat_map(&:children).grep(Sirena::Svg::Path)

      expect(paths).not_to be_empty
    end
  end
end
