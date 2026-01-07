# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::Renderer::BlockRenderer do
  let(:theme) { Sirena::Theme::Registry.get(:default) }
  let(:renderer) { described_class.new(theme: theme) }

  describe '#render' do
    context 'with basic layout' do
      let(:layout) do
        {
          blocks: {
            'A' => {
              block: Sirena::Diagram::Block.new.tap { |b| b.id = 'A'; b.label = 'Block A' },
              x: 20,
              y: 20,
              width: 100,
              height: 60
            },
            'B' => {
              block: Sirena::Diagram::Block.new.tap { |b| b.id = 'B'; b.label = 'Block B' },
              x: 140,
              y: 20,
              width: 100,
              height: 60
            }
          },
          connections: [],
          columns: 2,
          width: 260,
          height: 100
        }
      end

      it 'renders SVG document' do
        svg = renderer.render(layout)
        expect(svg).to be_a(Sirena::Svg::Document)
        expect(svg.width).to eq(260)
        expect(svg.height).to eq(100)
      end

      it 'renders blocks' do
        svg = renderer.render(layout)
        xml = svg.to_xml
        expect(xml).to include('Block A')
        expect(xml).to include('Block B')
      end
    end

    context 'with connections' do
      let(:layout) do
        {
          blocks: {
            'A' => {
              block: Sirena::Diagram::Block.new.tap { |b| b.id = 'A'; b.label = 'A' },
              x: 20,
              y: 20,
              width: 100,
              height: 60
            },
            'B' => {
              block: Sirena::Diagram::Block.new.tap { |b| b.id = 'B'; b.label = 'B' },
              x: 20,
              y: 100,
              width: 100,
              height: 60
            }
          },
          connections: [
            {
              from: 'A',
              to: 'B',
              from_x: 70,
              from_y: 80,
              to_x: 70,
              to_y: 100,
              connection_type: 'arrow'
            }
          ],
          columns: 1,
          width: 140,
          height: 180
        }
      end

      it 'renders connections' do
        svg = renderer.render(layout)
        xml = svg.to_xml
        expect(xml).to include('<path')
        expect(xml).to include('marker-end')
      end
    end

    context 'with circle shape' do
      let(:layout) do
        {
          blocks: {
            'A' => {
              block: Sirena::Diagram::Block.new.tap do |b|
                b.id = 'A'
                b.label = 'Circle'
                b.shape = 'circle'
              end,
              x: 20,
              y: 20,
              width: 80,
              height: 80
            }
          },
          connections: [],
          columns: 1,
          width: 120,
          height: 120
        }
      end

      it 'renders circle shape' do
        svg = renderer.render(layout)
        xml = svg.to_xml
        expect(xml).to include('<circle')
      end
    end
  end
end