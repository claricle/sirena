# frozen_string_literal: true

require 'spec_helper'
require 'sirena/renderer/user_journey'

RSpec.describe Sirena::Renderer::UserJourneyRenderer do
  let(:renderer) { described_class.new }

  describe '#render' do
    let(:graph) do
      {
        id: 'user_journey',
        children: [
          {
            id: 'task_0',
            x: 100,
            y: 100,
            width: 150,
            height: 80,
            metadata: {
              name: 'Browse products',
              score: 5,
              score_color: :green,
              actors: ['Customer'],
              section_name: 'Shopping'
            }
          }
        ],
        edges: [],
        metadata: {
          title: 'My Journey',
          sections: ['Shopping']
        }
      }
    end

    it 'renders graph to SVG document' do
      svg = renderer.render(graph)

      expect(svg).to be_a(Sirena::Svg::Document)
      expect(svg.width).to be > 0
      expect(svg.height).to be > 0
    end

    it 'includes task boxes in SVG' do
      svg = renderer.render(graph)

      groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group)
      end

      expect(groups.length).to be > 0
      expect(groups.first.id).to include('task-')
    end

    it 'renders task boxes as rectangles' do
      svg = renderer.render(graph)

      groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group)
      end

      rects = groups.flat_map(&:children).select do |c|
        c.is_a?(Sirena::Svg::Rect)
      end

      expect(rects).not_to be_empty
    end

    it 'uses score-based colors for task boxes' do
      svg = renderer.render(graph)

      groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group) && c.id&.include?('task-')
      end

      rects = groups.flat_map(&:children).select do |c|
        c.is_a?(Sirena::Svg::Rect)
      end

      expect(rects.first.fill).to eq('#48dbfb')
    end

    it 'renders task content as text elements' do
      svg = renderer.render(graph)

      groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group)
      end

      texts = groups.flat_map(&:children).select do |c|
        c.is_a?(Sirena::Svg::Text)
      end

      expect(texts).not_to be_empty
    end

    it 'renders title as text element' do
      svg = renderer.render(graph)

      texts = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Text)
      end

      title_text = texts.find { |t| t.content == 'My Journey' }
      expect(title_text).not_to be_nil
    end

    it 'renders section headers as text elements' do
      svg = renderer.render(graph)

      texts = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Text)
      end

      section_text = texts.find { |t| t.content == 'Shopping' }
      expect(section_text).not_to be_nil
    end

    it 'renders timeline arrows between tasks' do
      graph_with_edges = graph.dup
      graph_with_edges[:children] << {
        id: 'task_1',
        x: 300,
        y: 100,
        width: 150,
        height: 80,
        metadata: {
          name: 'Select item',
          score: 4,
          score_color: :green,
          actors: ['Customer'],
          section_name: 'Shopping'
        }
      }
      graph_with_edges[:edges] = [
        {
          id: 'flow_0',
          sources: ['task_0'],
          targets: ['task_1'],
          metadata: { type: 'sequence' }
        }
      ]

      svg = renderer.render(graph_with_edges)

      groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group) && c.id&.include?('arrow-')
      end

      expect(groups).not_to be_empty
    end
  end
end
