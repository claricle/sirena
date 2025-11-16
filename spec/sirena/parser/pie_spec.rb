# frozen_string_literal: true

require 'spec_helper'
require 'sirena/parser/pie'
require 'sirena/transform/pie'
require 'sirena/renderer/pie'

RSpec.describe Sirena::Parser::PieParser do
  let(:parser) { described_class.new }
  let(:transform) { Sirena::Transform::PieTransform.new }
  let(:renderer) { Sirena::Renderer::PieRenderer.new }

  describe '#parse' do
    context 'with simple pie chart' do
      let(:source) do
        <<~MERMAID
          pie
                "Apples": 42
                "Oranges": 58
        MERMAID
      end

      it 'parses successfully' do
        diagram = parser.parse(source)
        expect(diagram).to be_a(Sirena::Diagram::Pie)
        expect(diagram.slices.length).to eq(2)
        expect(diagram.slices[0].label).to eq('Apples')
        expect(diagram.slices[0].value).to eq(42.0)
        expect(diagram.slices[1].label).to eq('Oranges')
        expect(diagram.slices[1].value).to eq(58.0)
      end
    end

    context 'with title' do
      let(:source) do
        <<~MERMAID
          pie title Sales Distribution
                "Product A": 45
                "Product B": 55
        MERMAID
      end

      it 'parses title correctly' do
        diagram = parser.parse(source)
        expect(diagram.title).to eq('Sales Distribution')
        expect(diagram.slices.length).to eq(2)
      end
    end

    context 'with showData flag' do
      let(:source) do
        <<~MERMAID
          pie showData
                "Category A": 100
                "Category B": 50
        MERMAID
      end

      it 'sets show_data flag' do
        diagram = parser.parse(source)
        expect(diagram.show_data).to be true
        expect(diagram.slices.length).to eq(2)
      end
    end

    context 'with comments' do
      let(:source) do
        <<~MERMAID
          pie
                %% This is a comment
                "Item 1": 30
                "Item 2": 70
        MERMAID
      end

      it 'ignores comments' do
        diagram = parser.parse(source)
        expect(diagram.slices.length).to eq(2)
      end
    end

    context 'with accessibility features' do
      let(:source) do
        <<~MERMAID
          pie title Sales Chart
                accTitle: Accessible Title
                accDescr: This chart shows sales distribution
                "Q1": 25
                "Q2": 75
        MERMAID
      end

      it 'parses accessibility attributes' do
        diagram = parser.parse(source)
        expect(diagram.title).to eq('Sales Chart')
        expect(diagram.acc_title).to eq('Accessible Title')
        expect(diagram.acc_description).to eq('This chart shows sales distribution')
      end
    end

    context 'with decimal values' do
      let(:source) do
        <<~MERMAID
          pie
                "First": 42.5
                "Second": 57.5
        MERMAID
      end

      it 'handles decimal values' do
        diagram = parser.parse(source)
        expect(diagram.slices[0].value).to eq(42.5)
        expect(diagram.slices[1].value).to eq(57.5)
      end
    end

    context 'with negative values' do
      let(:source) do
        <<~MERMAID
          pie
                "Positive": 100
                "Negative": -50
        MERMAID
      end

      it 'handles negative values' do
        diagram = parser.parse(source)
        expect(diagram.slices[1].value).to eq(-50.0)
      end
    end

    context 'with empty diagram' do
      let(:source) { 'pie' }

      it 'parses empty diagram' do
        diagram = parser.parse(source)
        expect(diagram).to be_a(Sirena::Diagram::Pie)
        expect(diagram.slices).to be_empty
        expect(diagram.valid?).to be true
      end
    end

    context 'with case-insensitive pie keyword' do
      it 'parses "Pie Chart"' do
        diagram = parser.parse('Pie Chart')
        expect(diagram).to be_a(Sirena::Diagram::Pie)
      end

      it 'parses "pie chart"' do
        diagram = parser.parse('pie chart')
        expect(diagram).to be_a(Sirena::Diagram::Pie)
      end

      it 'parses "pie"' do
        diagram = parser.parse('pie')
        expect(diagram).to be_a(Sirena::Diagram::Pie)
      end
    end
  end

  describe 'transform and render pipeline' do
    let(:source) do
      <<~MERMAID
        pie title Product Distribution
              "Product A": 45
              "Product B": 30
              "Product C": 25
      MERMAID
    end

    it 'produces valid SVG output' do
      diagram = parser.parse(source)
      graph = transform.to_graph(diagram)
      svg = renderer.render(graph)

      expect(svg).to be_a(Sirena::Svg::Document)
      expect(svg.width).to be > 0
      expect(svg.height).to be > 0
      expect(svg.children).not_to be_empty
    end

    it 'calculates correct percentages and angles' do
      diagram = parser.parse(source)
      graph = transform.to_graph(diagram)

      expect(graph[:slices].length).to eq(3)
      expect(graph[:slices][0][:percentage]).to eq(45.0)
      expect(graph[:slices][1][:percentage]).to eq(30.0)
      expect(graph[:slices][2][:percentage]).to eq(25.0)

      # Total should be 360 degrees
      total_angle = graph[:slices].sum { |s| s[:angle] }
      expect(total_angle).to be_within(0.1).of(360.0)
    end
  end
end