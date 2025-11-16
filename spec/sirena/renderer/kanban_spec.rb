# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::Renderer::Kanban do
  let(:theme) { Sirena::Theme::Registry.get(:default) }
  let(:renderer) { described_class.new(theme: theme) }

  describe '#render' do
    context 'with a simple kanban board' do
      let(:layout) do
        {
          columns: [
            {
              id: 'todo',
              title: 'Todo',
              x: 0,
              y: 0,
              width: 200,
              height: 150,
              card_count: 1
            }
          ],
          cards: [
            {
              id: 'docs',
              text: 'Create Documentation',
              column_id: 'todo',
              x: 10,
              y: 60,
              width: 180,
              height: 80,
              metadata: {},
              has_metadata: false
            }
          ],
          width: 200,
          height: 150
        }
      end

      it 'renders an SVG document' do
        svg = renderer.render(layout)
        expect(svg).to be_a(Sirena::Svg::Document)
      end

      it 'includes column elements' do
        svg = renderer.render(layout)
        xml = svg.to_xml
        expect(xml).to include('rect')
        expect(xml).to include('Todo')
      end

      it 'includes card elements' do
        svg = renderer.render(layout)
        xml = svg.to_xml
        expect(xml).to include('Create Documentation')
      end
    end

    context 'with multiple columns' do
      let(:layout) do
        {
          columns: [
            {
              id: 'todo',
              title: 'Todo',
              x: 0,
              y: 0,
              width: 200,
              height: 150,
              card_count: 1
            },
            {
              id: 'done',
              title: 'Done',
              x: 260,
              y: 0,
              width: 200,
              height: 150,
              card_count: 1
            }
          ],
          cards: [
            {
              id: 'docs',
              text: 'Create Documentation',
              column_id: 'todo',
              x: 10,
              y: 60,
              width: 180,
              height: 80,
              metadata: {},
              has_metadata: false
            },
            {
              id: 'release',
              text: 'Release v1.0',
              column_id: 'done',
              x: 270,
              y: 60,
              width: 180,
              height: 80,
              metadata: {},
              has_metadata: false
            }
          ],
          width: 460,
          height: 150
        }
      end

      it 'renders all columns' do
        svg = renderer.render(layout)
        xml = svg.to_xml
        expect(xml).to include('Todo')
        expect(xml).to include('Done')
      end

      it 'renders all cards' do
        svg = renderer.render(layout)
        xml = svg.to_xml
        expect(xml).to include('Create Documentation')
        expect(xml).to include('Release v1.0')
      end
    end

    context 'with card metadata' do
      let(:layout) do
        {
          columns: [
            {
              id: 'todo',
              title: 'Todo',
              x: 0,
              y: 0,
              width: 200,
              height: 180,
              card_count: 1
            }
          ],
          cards: [
            {
              id: 'docs',
              text: 'Create Documentation',
              column_id: 'todo',
              x: 10,
              y: 60,
              width: 180,
              height: 110,
              metadata: {
                priority: 'High',
                ticket: 'MC-1001'
              },
              has_metadata: true
            }
          ],
          width: 200,
          height: 180
        }
      end

      it 'renders metadata' do
        svg = renderer.render(layout)
        xml = svg.to_xml
        expect(xml).to include('Priority')
        expect(xml).to include('High')
        expect(xml).to include('Ticket')
        expect(xml).to include('MC-1001')
      end
    end

    context 'with empty board' do
      let(:layout) do
        {
          columns: [],
          cards: [],
          width: 0,
          height: 0
        }
      end

      it 'renders without errors' do
        expect { renderer.render(layout) }.not_to raise_error
      end
    end
  end
end