# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::Parser::FlowchartParser do
  let(:parser) { described_class.new }

  describe '#parse' do
    it 'parses simple flowchart with two nodes' do
      source = "graph TD\nA[Start]-->B[End]"
      diagram = parser.parse(source)

      expect(diagram).to be_a(Sirena::Diagram::Flowchart)
      expect(diagram.direction).to eq('TD')
      expect(diagram.nodes.length).to eq(2)
      expect(diagram.edges.length).to eq(1)
    end

    it 'parses node with rectangle shape' do
      source = "graph TD\nA[Label Text]"
      diagram = parser.parse(source)

      node = diagram.find_node('A')
      expect(node).not_to be_nil
      expect(node.label).to eq('Label Text')
      expect(node.shape).to eq('rect')
    end

    it 'parses node with rounded shape' do
      source = "graph TD\nA(Rounded Label)"
      diagram = parser.parse(source)

      node = diagram.find_node('A')
      expect(node).not_to be_nil
      expect(node.label).to eq('Rounded Label')
      expect(node.shape).to eq('rounded')
    end

    it 'parses node with rhombus shape' do
      source = "graph TD\nA{Decision}"
      diagram = parser.parse(source)

      node = diagram.find_node('A')
      expect(node).not_to be_nil
      expect(node.label).to eq('Decision')
      expect(node.shape).to eq('rhombus')
    end

    it 'parses multiple edges in sequence' do
      source = "graph TD\nA-->B-->C"
      diagram = parser.parse(source)

      expect(diagram.nodes.length).to eq(3)
      expect(diagram.edges.length).to eq(2)

      edge1 = diagram.edges[0]
      expect(edge1.source_id).to eq('A')
      expect(edge1.target_id).to eq('B')

      edge2 = diagram.edges[1]
      expect(edge2.source_id).to eq('B')
      expect(edge2.target_id).to eq('C')
    end

    it 'parses flowchart with LR direction' do
      source = "graph LR\nA-->B"
      diagram = parser.parse(source)

      expect(diagram.direction).to eq('LR')
    end

    it 'raises ParseError for invalid syntax' do
      source = 'invalid syntax'
      expect { parser.parse(source) }.to raise_error(
        Sirena::Parser::ParseError
      )
    end
  end
end
