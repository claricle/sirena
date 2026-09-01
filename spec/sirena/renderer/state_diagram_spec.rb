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

      groups = svg.children.grep(Sirena::Svg::Group)
      expect(groups.length).to be > 0
    end

    it 'renders normal states as rounded rectangles' do
      svg = renderer.render(graph)

      groups = svg.children.grep(Sirena::Svg::Group)

      rects = groups.flat_map(&:children).grep(Sirena::Svg::Rect)

      expect(rects).not_to be_empty
      expect(rects.first.rx).to eq(10)
    end

    it 'renders start state as filled circle' do
      graph[:children][0][:metadata][:state_type] = 'start'

      svg = renderer.render(graph)

      groups = svg.children.grep(Sirena::Svg::Group)

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
              gc.children.grep(Sirena::Svg::Circle)
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

      groups = svg.children.grep(Sirena::Svg::Group)

      polygons = groups.flat_map(&:children).grep(Sirena::Svg::Polygon)

      expect(polygons).not_to be_empty
    end

    it 'renders fork state as thick bar' do
      graph[:children][0][:metadata][:state_type] = 'fork'

      svg = renderer.render(graph)

      groups = svg.children.grep(Sirena::Svg::Group)

      rects = groups.flat_map(&:children).select do |c|
        c.is_a?(Sirena::Svg::Rect) && c.fill == '#000000'
      end

      expect(rects).not_to be_empty
    end

    it 'renders state labels as text elements' do
      svg = renderer.render(graph)

      groups = svg.children.grep(Sirena::Svg::Group)

      texts = groups.flat_map(&:children).grep(Sirena::Svg::Text)

      expect(texts).not_to be_empty
      expect(texts.map(&:content)).to include('Idle')
    end

    it 'keeps accumulated state text inside its rectangle' do
      diagram = Sirena::Parser::StateDiagramParser.new.parse(<<~MERMAID)
        stateDiagram-v2
        state "ALIAS_ONE" as A
        A : DESC_ONE
        state "ALIAS_TWO" as A
        A : DESC_TWO
      MERMAID
      rendered_graph = Sirena::Transform::StateDiagramTransform.new
        .to_graph(diagram)
      svg = renderer.render(rendered_graph)
      state_group = svg.children.find { |child| child.id == 'state-A' }
      rectangle = state_group.children.grep(Sirena::Svg::Rect).first
      texts = state_group.children.grep(Sirena::Svg::Text)

      text_bounds = texts.zip(rendered_graph[:children].first[:labels]).map do |text, label|
        [text.y - (label[:height] / 2), text.y + (label[:height] / 2)]
      end
      expect(text_bounds.flatten.min).to be >= rectangle.y
      expect(text_bounds.flatten.max).to be <= rectangle.y + rectangle.height
    end

    it 'renders transitions as paths' do
      svg = renderer.render(graph)

      groups = svg.children.grep(Sirena::Svg::Group)

      paths = groups.flat_map(&:children).grep(Sirena::Svg::Path)

      expect(paths).not_to be_empty
    end

    it 'renders transition labels' do
      svg = renderer.render(graph)

      groups = svg.children.grep(Sirena::Svg::Group)

      texts = groups.flat_map(&:children).select do |c|
        c.is_a?(Sirena::Svg::Text) && c.content == 'start'
      end

      expect(texts).not_to be_empty
    end
  end
end
