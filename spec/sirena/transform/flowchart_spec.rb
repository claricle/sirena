# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::Transform::FlowchartTransform do
  let(:transform) { described_class.new }

  describe '#to_graph' do
    let(:diagram) do
      Sirena::Diagram::Flowchart.new(direction: 'TD').tap do |d|
        d.nodes << Sirena::Diagram::FlowchartNode.new(
          id: 'A',
          label: 'Start',
          shape: 'rect'
        )
        d.nodes << Sirena::Diagram::FlowchartNode.new(
          id: 'B',
          label: 'End',
          shape: 'rect'
        )
        d.edges << Sirena::Diagram::FlowchartEdge.new(
          source_id: 'A',
          target_id: 'B',
          arrow_type: 'arrow'
        )
      end
    end

    it 'converts diagram to graph structure' do
      graph = transform.to_graph(diagram)

      expect(graph).to be_a(Hash)
      expect(graph[:id]).to eq('flowchart')
      expect(graph[:children]).to be_an(Array)
      expect(graph[:edges]).to be_an(Array)
      expect(graph[:layoutOptions]).to be_a(Hash)
    end

    it 'creates nodes with dimensions' do
      graph = transform.to_graph(diagram)

      expect(graph[:children].length).to eq(2)

      node_a = graph[:children].find { |n| n[:id] == 'A' }
      expect(node_a).not_to be_nil
      expect(node_a[:width]).to be > 0
      expect(node_a[:height]).to be > 0
      expect(node_a[:labels]).to be_an(Array)
      expect(node_a[:labels].first[:text]).to eq('Start')
    end

    it 'creates edges with metadata' do
      graph = transform.to_graph(diagram)

      expect(graph[:edges].length).to eq(1)

      edge = graph[:edges].first
      expect(edge[:sources]).to eq(['A'])
      expect(edge[:targets]).to eq(['B'])
      expect(edge[:metadata][:arrow_type]).to eq('arrow')
    end

    it 'sets layout options based on direction' do
      graph = transform.to_graph(diagram)

      options = graph[:layoutOptions]
      expect(options['algorithm']).to eq('layered')
      expect(options['elk.direction']).to eq('DOWN')
    end

    it 'converts LR direction to RIGHT layout' do
      diagram.direction = 'LR'
      graph = transform.to_graph(diagram)

      expect(graph[:layoutOptions]['elk.direction']).to eq('RIGHT')
    end

    it 'raises error for invalid diagram' do
      invalid_diagram = Sirena::Diagram::Flowchart.new

      expect do
        transform.to_graph(invalid_diagram)
      end.to raise_error(Sirena::Transform::TransformError)
    end
  end
end
