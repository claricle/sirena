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

    # What the renderer can reach, not what the model happens to hold.
    # An empty box is never carried into the layout, so an edge naming
    # one resolves to nothing and is dropped.
    it 'returns false when an edge names a box nobody draws' do
      flowchart = described_class.new(direction: 'TD')
      flowchart.nodes << Sirena::Diagram::FlowchartNode.new(id: 'A',
                                                            label: 'A')
      flowchart.subgraphs << Sirena::Diagram::FlowchartSubgraph.new(id: 's')
      flowchart.edges << Sirena::Diagram::FlowchartEdge.new(source_id: 's',
                                                            target_id: 'A')

      expect(flowchart.valid?).to be false
    end

    it 'takes an edge that names a box somebody draws' do
      flowchart = described_class.new(direction: 'TD')
      flowchart.nodes << Sirena::Diagram::FlowchartNode.new(id: 'A',
                                                            label: 'A')
      flowchart.subgraphs << Sirena::Diagram::FlowchartSubgraph.new(
        id: 's', node_ids: %w[A]
      )
      flowchart.edges << Sirena::Diagram::FlowchartEdge.new(source_id: 's',
                                                            target_id: 'A')

      expect(flowchart.valid?).to be true
    end

    # A box cannot be its own ancestor. The layout hangs each box off
    # its parent, so a loop leaves the diagram with no root at all: the
    # transform finds nothing to place while still counting the looped
    # boxes' nodes as spoken for, and the drawing comes out empty. The
    # model used to call that valid.
    #
    # Only reachable by hand. The parser refuses the source first, and
    # every parent edge it can set is present in the containment graph
    # it checks, so an acyclic parse cannot produce a cyclic model.
    it 'returns false when a box is its own parent' do
      flowchart = described_class.new(direction: 'TD')
      flowchart.nodes << Sirena::Diagram::FlowchartNode.new(id: 'A',
                                                            label: 'A')
      flowchart.subgraphs << Sirena::Diagram::FlowchartSubgraph.new(
        id: 's', parent_id: 's', node_ids: %w[A]
      )

      expect(flowchart.valid?).to be false
    end

    it 'returns false when two boxes are parented to each other' do
      flowchart = described_class.new(direction: 'TD')
      %w[A B].each do |id|
        flowchart.nodes << Sirena::Diagram::FlowchartNode.new(id: id,
                                                              label: id)
      end
      flowchart.subgraphs << Sirena::Diagram::FlowchartSubgraph.new(
        id: 'x', parent_id: 'y', node_ids: %w[A]
      )
      flowchart.subgraphs << Sirena::Diagram::FlowchartSubgraph.new(
        id: 'y', parent_id: 'x', node_ids: %w[B]
      )

      expect(flowchart.valid?).to be false
    end

    # A pair is the shape that was found; the walk has to close a longer
    # ring too, or the guard is proven in one direction only.
    it 'returns false when three boxes close a ring' do
      flowchart = described_class.new(direction: 'TD')
      flowchart.nodes << Sirena::Diagram::FlowchartNode.new(id: 'A',
                                                            label: 'A')
      %w[p q r].zip(%w[q r p]).each do |id, parent|
        flowchart.subgraphs << Sirena::Diagram::FlowchartSubgraph.new(
          id: id, parent_id: parent, node_ids: %w[A]
        )
      end

      expect(flowchart.valid?).to be false
    end

    # The rings above prove the guard fires. This proves it does not
    # fire on a chain of the same depth, which is the shape a real
    # three-deep nesting has.
    it 'takes three boxes nested one inside the next' do
      flowchart = described_class.new(direction: 'TD')
      flowchart.nodes << Sirena::Diagram::FlowchartNode.new(id: 'A',
                                                            label: 'A')
      flowchart.subgraphs << Sirena::Diagram::FlowchartSubgraph.new(
        id: 'outer', child_ids: %w[middle]
      )
      flowchart.subgraphs << Sirena::Diagram::FlowchartSubgraph.new(
        id: 'middle', parent_id: 'outer', child_ids: %w[inner]
      )
      flowchart.subgraphs << Sirena::Diagram::FlowchartSubgraph.new(
        id: 'inner', parent_id: 'middle', node_ids: %w[A]
      )

      expect(flowchart.valid?).to be true
    end

    # Naming a parent nobody declared is not a loop. The transform
    # already puts such a box at the top level, so refusing it here
    # would reject a diagram that draws perfectly well.
    it 'takes a box whose parent is not in the diagram' do
      flowchart = described_class.new(direction: 'TD')
      flowchart.nodes << Sirena::Diagram::FlowchartNode.new(id: 'A',
                                                            label: 'A')
      flowchart.subgraphs << Sirena::Diagram::FlowchartSubgraph.new(
        id: 's', parent_id: 'absent', node_ids: %w[A]
      )

      expect(flowchart.valid?).to be true
    end

    # Every node can end up naming a box, and mmdc draws the boxes. Both
    # boxes are present, the way a parse leaves them: `one` holds `e1`,
    # and `e1` holds nothing, so only `one` is worth drawing.
    it 'takes a diagram that is only boxes' do
      flowchart = described_class.new(direction: 'TD')
      flowchart.subgraphs << Sirena::Diagram::FlowchartSubgraph.new(
        id: 'one', child_ids: %w[e1]
      )
      flowchart.subgraphs << Sirena::Diagram::FlowchartSubgraph.new(
        id: 'e1', parent_id: 'one'
      )

      expect(flowchart.valid?).to be true
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
