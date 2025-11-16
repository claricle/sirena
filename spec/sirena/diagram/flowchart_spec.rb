# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::Diagram::Flowchart do
  describe '#diagram_type' do
    it 'returns :flowchart' do
      flowchart = described_class.new
      expect(flowchart.diagram_type).to eq(:flowchart)
    end
  end

  describe '#valid?' do
    it 'returns true for valid flowchart with nodes' do
      flowchart = described_class.new(direction: 'TD')
      flowchart.nodes << Sirena::Diagram::FlowchartNode.new(
        id: 'A',
        label: 'Start',
        shape: 'rect'
      )

      expect(flowchart.valid?).to be true
    end

    it 'returns false for flowchart without nodes' do
      flowchart = described_class.new(direction: 'TD')
      expect(flowchart.valid?).to be false
    end

    it 'returns false when edge references non-existent node' do
      flowchart = described_class.new(direction: 'TD')
      flowchart.nodes << Sirena::Diagram::FlowchartNode.new(
        id: 'A',
        label: 'Start',
        shape: 'rect'
      )
      flowchart.edges << Sirena::Diagram::FlowchartEdge.new(
        source_id: 'A',
        target_id: 'B',
        arrow_type: 'arrow'
      )

      expect(flowchart.valid?).to be false
    end
  end

  describe '#find_node' do
    let(:flowchart) { described_class.new }
    let(:node) do
      Sirena::Diagram::FlowchartNode.new(
        id: 'A',
        label: 'Test',
        shape: 'rect'
      )
    end

    before { flowchart.nodes << node }

    it 'finds node by id' do
      expect(flowchart.find_node('A')).to eq(node)
    end

    it 'returns nil for non-existent id' do
      expect(flowchart.find_node('Z')).to be_nil
    end
  end

  describe '#edges_from' do
    let(:flowchart) { described_class.new }
    let(:edge) do
      Sirena::Diagram::FlowchartEdge.new(
        source_id: 'A',
        target_id: 'B',
        arrow_type: 'arrow'
      )
    end

    before { flowchart.edges << edge }

    it 'finds edges originating from node' do
      expect(flowchart.edges_from('A')).to eq([edge])
    end

    it 'returns empty array for node with no outgoing edges' do
      expect(flowchart.edges_from('B')).to eq([])
    end
  end

  describe '#edges_to' do
    let(:flowchart) { described_class.new }
    let(:edge) do
      Sirena::Diagram::FlowchartEdge.new(
        source_id: 'A',
        target_id: 'B',
        arrow_type: 'arrow'
      )
    end

    before { flowchart.edges << edge }

    it 'finds edges targeting node' do
      expect(flowchart.edges_to('B')).to eq([edge])
    end

    it 'returns empty array for node with no incoming edges' do
      expect(flowchart.edges_to('A')).to eq([])
    end
  end
end
