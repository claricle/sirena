# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::Renderer::StateDiagramRenderer do
  let(:renderer) { described_class.new }

  describe '#render' do
    let(:graph) do
      {
        id: 'state_diagram',
        children: [
          {
            id: 'idle',
            x: 10,
            y: 10,
            width: 120,
            height: 60,
            labels: [{ text: 'Idle', width: 40, height: 14 }],
            metadata: { state_type: 'normal' }
          },
          {
            id: 'active',
            x: 180,
            y: 10,
            width: 120,
            height: 60,
            labels: [{ text: 'Active', width: 50, height: 14 }],
            metadata: { state_type: 'normal' }
          }
        ],
        edges: [
          {
            id: 'idle_to_active',
            sources: ['idle'],
            targets: ['active'],
            labels: [{ text: 'start', width: 40, height: 14 }],
            metadata: { trigger: 'start' }
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

    it 'includes states in SVG' do
      svg = renderer.render(graph)

      groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group)
      end
      expect(groups.length).to be > 0
    end

    it 'renders normal states as rounded rectangles' do
      svg = renderer.render(graph)

      groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group)
      end

      rects = groups.flat_map(&:children).select do |c|
        c.is_a?(Sirena::Svg::Rect)
      end

      expect(rects).not_to be_empty
      expect(rects.first.rx).to eq(10)
    end

    it 'renders start state as filled circle' do
      graph[:children][0][:metadata][:state_type] = 'start'

      svg = renderer.render(graph)

      groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group)
      end

      circles = groups.flat_map(&:children).select do |c|
        c.is_a?(Sirena::Svg::Circle) && c.fill == '#000000'
      end

      expect(circles).not_to be_empty
    end

    it 'renders end state as double circle' do
      graph[:children][0][:metadata][:state_type] = 'end'

      svg = renderer.render(graph)

      # Find all groups including nested ones
      all_circles = []
      svg.children.each do |child|
        next unless child.is_a?(Sirena::Svg::Group)

        child.children.each do |gc|
          if gc.is_a?(Sirena::Svg::Group)
            all_circles.concat(
              gc.children.select { |c| c.is_a?(Sirena::Svg::Circle) }
            )
          elsif gc.is_a?(Sirena::Svg::Circle)
            all_circles << gc
          end
        end
      end

      expect(all_circles.length).to be >= 2
    end

    it 'renders choice state as diamond' do
      graph[:children][0][:metadata][:state_type] = 'choice'

      svg = renderer.render(graph)

      groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group)
      end

      polygons = groups.flat_map(&:children).select do |c|
        c.is_a?(Sirena::Svg::Polygon)
      end

      expect(polygons).not_to be_empty
    end

    it 'renders fork state as thick bar' do
      graph[:children][0][:metadata][:state_type] = 'fork'

      svg = renderer.render(graph)

      groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group)
      end

      rects = groups.flat_map(&:children).select do |c|
        c.is_a?(Sirena::Svg::Rect) && c.fill == '#000000'
      end

      expect(rects).not_to be_empty
    end

    it 'renders state labels as text elements' do
      svg = renderer.render(graph)

      groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group)
      end

      texts = groups.flat_map(&:children).select do |c|
        c.is_a?(Sirena::Svg::Text)
      end

      expect(texts).not_to be_empty
      expect(texts.map(&:content)).to include('Idle')
    end

    it 'renders transitions as paths' do
      svg = renderer.render(graph)

      groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group)
      end

      paths = groups.flat_map(&:children).select do |c|
        c.is_a?(Sirena::Svg::Path)
      end

      expect(paths).not_to be_empty
    end

    it 'renders transition labels' do
      svg = renderer.render(graph)

      groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group)
      end

      texts = groups.flat_map(&:children).select do |c|
        c.is_a?(Sirena::Svg::Text) && c.content == 'start'
      end

      expect(texts).not_to be_empty
    end
  end
end
