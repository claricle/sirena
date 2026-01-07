# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Flowchart Integration' do
  describe 'complete flowchart pipeline' do
    let(:parser) { Sirena::Parser::FlowchartParser.new }
    let(:transform) { Sirena::Transform::FlowchartTransform.new }
    let(:renderer) { Sirena::Renderer::FlowchartRenderer.new }

    it 'parses, transforms, and renders a simple flowchart' do
      source = "graph TD\nA[Start]-->B[End]"

      # Parse
      diagram = parser.parse(source)
      expect(diagram).to be_a(Sirena::Diagram::Flowchart)
      expect(diagram.valid?).to be true

      # Transform
      graph = transform.to_graph(diagram)
      expect(graph).to be_a(Hash)
      expect(graph[:children].length).to eq(2)
      expect(graph[:edges].length).to eq(1)

      # Render (without elkrb layout, just with graph structure)
      svg = renderer.render(graph)
      expect(svg).to be_a(Sirena::Svg::Document)
      expect(svg.children).not_to be_empty
    end

    it 'handles multiple node shapes' do
      source = <<~MERMAID
        graph TD
        A[Rectangle]
        B(Rounded)
        C{Rhombus}
        A-->B-->C
      MERMAID

      diagram = parser.parse(source)

      expect(diagram.nodes.length).to eq(3)
      expect(diagram.find_node('A').shape).to eq('rect')
      expect(diagram.find_node('B').shape).to eq('rounded')
      expect(diagram.find_node('C').shape).to eq('rhombus')

      graph = transform.to_graph(diagram)
      svg = renderer.render(graph)

      expect(svg).to be_a(Sirena::Svg::Document)
    end

    it 'handles different directions' do
      source = "graph LR\nA-->B"

      diagram = parser.parse(source)
      expect(diagram.direction).to eq('LR')

      graph = transform.to_graph(diagram)
      expect(graph[:layoutOptions]['elk.direction']).to eq('RIGHT')
    end
  end

  describe 'DiagramRegistry integration' do
    it 'has flowchart registered' do
      expect(Sirena::DiagramRegistry.registered?(:flowchart)).to be true
    end

    it 'retrieves flowchart handlers' do
      handlers = Sirena::DiagramRegistry.get(:flowchart)

      expect(handlers).not_to be_nil
      expect(handlers[:parser]).to eq(
        Sirena::Parser::FlowchartParser
      )
      expect(handlers[:transform]).to eq(
        Sirena::Transform::FlowchartTransform
      )
      expect(handlers[:renderer]).to eq(
        Sirena::Renderer::FlowchartRenderer
      )
    end
  end
end
