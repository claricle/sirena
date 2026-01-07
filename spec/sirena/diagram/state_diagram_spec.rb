# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::Diagram::StateDiagram do
  describe '#diagram_type' do
    it 'returns :state_diagram' do
      diagram = described_class.new
      expect(diagram.diagram_type).to eq(:state_diagram)
    end
  end

  describe '#valid?' do
    it 'returns true for valid state diagram with states' do
      diagram = described_class.new(direction: 'TD')
      diagram.states << Sirena::Diagram::StateNode.new(
        id: 'idle',
        label: 'Idle',
        state_type: 'normal'
      )

      expect(diagram.valid?).to be true
    end

    it 'returns false for state diagram without states' do
      diagram = described_class.new(direction: 'TD')
      expect(diagram.valid?).to be false
    end

    it 'returns false when transition references non-existent state' do
      diagram = described_class.new(direction: 'TD')
      diagram.states << Sirena::Diagram::StateNode.new(
        id: 'idle',
        label: 'Idle',
        state_type: 'normal'
      )
      diagram.transitions << Sirena::Diagram::StateTransition.new(
        from_id: 'idle',
        to_id: 'active'
      )

      expect(diagram.valid?).to be false
    end
  end

  describe '#find_state' do
    let(:diagram) { described_class.new }
    let(:state) do
      Sirena::Diagram::StateNode.new(
        id: 'idle',
        label: 'Idle',
        state_type: 'normal'
      )
    end

    before { diagram.states << state }

    it 'finds state by id' do
      expect(diagram.find_state('idle')).to eq(state)
    end

    it 'returns nil for non-existent id' do
      expect(diagram.find_state('unknown')).to be_nil
    end
  end

  describe '#transitions_from' do
    let(:diagram) { described_class.new }
    let(:transition) do
      Sirena::Diagram::StateTransition.new(
        from_id: 'idle',
        to_id: 'active'
      )
    end

    before { diagram.transitions << transition }

    it 'finds transitions originating from state' do
      expect(diagram.transitions_from('idle')).to eq([transition])
    end

    it 'returns empty array for state with no outgoing transitions' do
      expect(diagram.transitions_from('active')).to eq([])
    end
  end

  describe '#transitions_to' do
    let(:diagram) { described_class.new }
    let(:transition) do
      Sirena::Diagram::StateTransition.new(
        from_id: 'idle',
        to_id: 'active'
      )
    end

    before { diagram.transitions << transition }

    it 'finds transitions targeting state' do
      expect(diagram.transitions_to('active')).to eq([transition])
    end

    it 'returns empty array for state with no incoming transitions' do
      expect(diagram.transitions_to('idle')).to eq([])
    end
  end

  describe '#start_state' do
    let(:diagram) { described_class.new }
    let(:start) do
      Sirena::Diagram::StateNode.new(
        id: 'start_1',
        label: '[*]',
        state_type: 'start'
      )
    end

    before { diagram.states << start }

    it 'finds the start state' do
      expect(diagram.start_state).to eq(start)
    end
  end

  describe '#end_states' do
    let(:diagram) { described_class.new }
    let(:end_state) do
      Sirena::Diagram::StateNode.new(
        id: 'end_1',
        label: '[*]',
        state_type: 'end'
      )
    end

    before { diagram.states << end_state }

    it 'finds all end states' do
      expect(diagram.end_states).to eq([end_state])
    end
  end

  describe '#composite_states' do
    let(:diagram) { described_class.new }
    let(:composite) do
      Sirena::Diagram::StateNode.new(
        id: 'composite',
        label: 'Composite',
        state_type: 'normal'
      ).tap do |s|
        s.children << Sirena::Diagram::StateNode.new(
          id: 'child',
          label: 'Child',
          state_type: 'normal'
        )
      end
    end

    before { diagram.states << composite }

    it 'finds all composite states' do
      expect(diagram.composite_states).to eq([composite])
    end
  end

  describe '#choice_states' do
    let(:diagram) { described_class.new }
    let(:choice) do
      Sirena::Diagram::StateNode.new(
        id: 'choice1',
        label: 'choice1',
        state_type: 'choice'
      )
    end

    before { diagram.states << choice }

    it 'finds all choice states' do
      expect(diagram.choice_states).to eq([choice])
    end
  end
end

RSpec.describe Sirena::Diagram::StateNode do
  describe '#valid?' do
    it 'returns true for valid state node' do
      node = described_class.new(
        id: 'idle',
        label: 'Idle',
        state_type: 'normal'
      )

      expect(node.valid?).to be true
    end

    it 'returns false for node without id' do
      node = described_class.new(label: 'Test', state_type: 'normal')
      expect(node.valid?).to be false
    end

    it 'returns false for node without state_type' do
      node = described_class.new(id: 'test', label: 'Test')
      node.state_type = nil
      expect(node.valid?).to be false
    end
  end

  describe '#start_state?' do
    it 'returns true for start state' do
      node = described_class.new(
        id: 'start',
        state_type: 'start'
      )
      expect(node.start_state?).to be true
    end

    it 'returns false for non-start state' do
      node = described_class.new(
        id: 'idle',
        state_type: 'normal'
      )
      expect(node.start_state?).to be false
    end
  end

  describe '#end_state?' do
    it 'returns true for end state' do
      node = described_class.new(
        id: 'end',
        state_type: 'end'
      )
      expect(node.end_state?).to be true
    end

    it 'returns false for non-end state' do
      node = described_class.new(
        id: 'idle',
        state_type: 'normal'
      )
      expect(node.end_state?).to be false
    end
  end

  describe '#choice_state?' do
    it 'returns true for choice state' do
      node = described_class.new(
        id: 'choice1',
        state_type: 'choice'
      )
      expect(node.choice_state?).to be true
    end
  end

  describe '#composite_state?' do
    it 'returns true when state has children' do
      node = described_class.new(
        id: 'composite',
        state_type: 'normal'
      )
      node.children << described_class.new(
        id: 'child',
        state_type: 'normal'
      )
      expect(node.composite_state?).to be true
    end

    it 'returns false when state has no children' do
      node = described_class.new(
        id: 'simple',
        state_type: 'normal'
      )
      expect(node.composite_state?).to be false
    end
  end
end

RSpec.describe Sirena::Diagram::StateTransition do
  describe '#valid?' do
    it 'returns true for valid transition' do
      transition = described_class.new(
        from_id: 'idle',
        to_id: 'active'
      )

      expect(transition.valid?).to be true
    end

    it 'returns false for transition without from_id' do
      transition = described_class.new(to_id: 'active')
      expect(transition.valid?).to be false
    end

    it 'returns false for transition without to_id' do
      transition = described_class.new(from_id: 'idle')
      expect(transition.valid?).to be false
    end
  end

  describe '#label' do
    it 'returns trigger only when no guard' do
      transition = described_class.new(
        from_id: 'idle',
        to_id: 'active',
        trigger: 'start'
      )

      expect(transition.label).to eq('start')
    end

    it 'returns trigger and guard when both present' do
      transition = described_class.new(
        from_id: 'idle',
        to_id: 'active',
        trigger: 'start',
        guard_condition: 'ready'
      )

      expect(transition.label).to eq('start [ready]')
    end

    it 'returns empty string when neither trigger nor guard' do
      transition = described_class.new(
        from_id: 'idle',
        to_id: 'active'
      )

      expect(transition.label).to eq('')
    end
  end
end
