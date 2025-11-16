# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::Transform::StateDiagramTransform do
  let(:transform) { described_class.new }

  describe '#to_graph' do
    let(:diagram) do
      Sirena::Diagram::StateDiagram.new(direction: 'TD').tap do |d|
        d.states << Sirena::Diagram::StateNode.new(
          id: 'idle',
          label: 'Idle',
          state_type: 'normal'
        )
        d.states << Sirena::Diagram::StateNode.new(
          id: 'active',
          label: 'Active',
          state_type: 'normal'
        )
        d.transitions << Sirena::Diagram::StateTransition.new(
          from_id: 'idle',
          to_id: 'active',
          trigger: 'start'
        )
      end
    end

    it 'converts diagram to graph structure' do
      graph = transform.to_graph(diagram)

      expect(graph).to be_a(Hash)
      expect(graph[:id]).to eq('state_diagram')
      expect(graph[:children]).to be_an(Array)
      expect(graph[:edges]).to be_an(Array)
      expect(graph[:layoutOptions]).to be_a(Hash)
    end

    it 'creates states with dimensions' do
      graph = transform.to_graph(diagram)

      expect(graph[:children].length).to eq(2)

      state_idle = graph[:children].find { |s| s[:id] == 'idle' }
      expect(state_idle).not_to be_nil
      expect(state_idle[:width]).to be > 0
      expect(state_idle[:height]).to be > 0
      expect(state_idle[:labels]).to be_an(Array)
      expect(state_idle[:labels].first[:text]).to eq('Idle')
      expect(state_idle[:metadata][:state_type]).to eq('normal')
    end

    it 'creates transitions with metadata' do
      graph = transform.to_graph(diagram)

      expect(graph[:edges].length).to eq(1)

      transition = graph[:edges].first
      expect(transition[:sources]).to eq(['idle'])
      expect(transition[:targets]).to eq(['active'])
      expect(transition[:metadata][:trigger]).to eq('start')
    end

    it 'handles start state dimensions' do
      diagram.states.clear
      diagram.transitions.clear
      diagram.states << Sirena::Diagram::StateNode.new(
        id: 'start_1',
        label: '[*]',
        state_type: 'start'
      )
      diagram.states << Sirena::Diagram::StateNode.new(
        id: 'idle',
        label: 'Idle',
        state_type: 'normal'
      )
      diagram.transitions << Sirena::Diagram::StateTransition.new(
        from_id: 'start_1',
        to_id: 'idle'
      )

      graph = transform.to_graph(diagram)

      start = graph[:children].find { |s| s[:id] == 'start_1' }
      expect(start[:width]).to eq(30)
      expect(start[:height]).to eq(30)
    end

    it 'handles choice state dimensions' do
      diagram.states.clear
      diagram.transitions.clear
      diagram.states << Sirena::Diagram::StateNode.new(
        id: 'choice1',
        label: 'choice1',
        state_type: 'choice'
      )
      diagram.states << Sirena::Diagram::StateNode.new(
        id: 'idle',
        label: 'Idle',
        state_type: 'normal'
      )
      diagram.transitions << Sirena::Diagram::StateTransition.new(
        from_id: 'choice1',
        to_id: 'idle'
      )

      graph = transform.to_graph(diagram)

      choice = graph[:children].find { |s| s[:id] == 'choice1' }
      expect(choice[:width]).to be > 0
      expect(choice[:height]).to be > 0
      expect(choice[:metadata][:state_type]).to eq('choice')
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
      invalid_diagram = Sirena::Diagram::StateDiagram.new

      expect do
        transform.to_graph(invalid_diagram)
      end.to raise_error(Sirena::Transform::TransformError)
    end

    it 'includes description in labels when present' do
      diagram.states.clear
      diagram.transitions.clear
      diagram.states << Sirena::Diagram::StateNode.new(
        id: 'idle',
        label: 'Idle',
        state_type: 'normal',
        description: 'System is idle'
      )
      diagram.states << Sirena::Diagram::StateNode.new(
        id: 'active',
        label: 'Active',
        state_type: 'normal'
      )
      diagram.transitions << Sirena::Diagram::StateTransition.new(
        from_id: 'idle',
        to_id: 'active'
      )

      graph = transform.to_graph(diagram)

      state = graph[:children].find { |s| s[:id] == 'idle' }
      expect(state[:labels].length).to eq(2)
      expect(state[:labels][0][:text]).to eq('Idle')
      expect(state[:labels][1][:text]).to eq('System is idle')
    end
  end
end
