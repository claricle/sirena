# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::Parser::StateDiagramParser do
  let(:parser) { described_class.new }

  describe '#parse' do
    it 'parses simple state diagram with two states' do
      source = "stateDiagram-v2\nIdle-->Active"
      diagram = parser.parse(source)

      expect(diagram).to be_a(Sirena::Diagram::StateDiagram)
      expect(diagram.states.length).to eq(2)
      expect(diagram.transitions.length).to eq(1)
    end

    it 'parses state diagram with start state' do
      source = "stateDiagram-v2\n[*]-->Idle"
      diagram = parser.parse(source)

      start_state = diagram.start_state
      expect(start_state).not_to be_nil
      expect(start_state.state_type).to eq('start')
      expect(diagram.transitions.length).to eq(1)
    end

    it 'parses state diagram with end state' do
      source = "stateDiagram-v2\nActive-->[*]"
      diagram = parser.parse(source)

      end_states = diagram.end_states
      expect(end_states.length).to eq(1)
      expect(end_states.first.state_type).to eq('end')
    end

    it 'parses complete state machine' do
      source = "stateDiagram-v2\n[*]-->Idle\nIdle-->Active\nActive-->[*]"
      diagram = parser.parse(source)

      expect(diagram.states.length).to eq(4)
      expect(diagram.transitions.length).to eq(3)
      expect(diagram.start_state).not_to be_nil
      expect(diagram.end_states.length).to eq(1)
    end

    it 'parses transition with trigger' do
      source = "stateDiagram-v2\nIdle-->Active: start"
      diagram = parser.parse(source)

      transition = diagram.transitions.first
      expect(transition.trigger).to eq('start')
      expect(transition.guard_condition).to be_nil
    end

    it 'parses transition with trigger and guard' do
      source = "stateDiagram-v2\nIdle-->Active: start [ready]"
      diagram = parser.parse(source)

      transition = diagram.transitions.first
      expect(transition.trigger).to eq('start')
      expect(transition.guard_condition).to eq('ready')
    end

    it 'parses choice state' do
      source = "stateDiagram-v2\nstate choice1 <<choice>>"
      diagram = parser.parse(source)

      choice = diagram.find_state('choice1')
      expect(choice).not_to be_nil
      expect(choice.state_type).to eq('choice')
    end

    it 'parses fork state' do
      source = "stateDiagram-v2\nstate fork1 <<fork>>"
      diagram = parser.parse(source)

      fork = diagram.find_state('fork1')
      expect(fork).not_to be_nil
      expect(fork.state_type).to eq('fork')
    end

    it 'parses join state' do
      source = "stateDiagram-v2\nstate join1 <<join>>"
      diagram = parser.parse(source)

      join = diagram.find_state('join1')
      expect(join).not_to be_nil
      expect(join.state_type).to eq('join')
    end

    it 'parses state with description' do
      source = "stateDiagram-v2\nstate Idle: System is idle"
      diagram = parser.parse(source)

      state = diagram.find_state('Idle')
      expect(state).not_to be_nil
      expect(state.description).to eq('System is idle')
    end

    it 'parses state diagram with TD direction' do
      source = "stateDiagram-v2 TD\nIdle-->Active"
      diagram = parser.parse(source)

      expect(diagram.direction).to eq('TD')
    end

    it 'parses state diagram with LR direction' do
      source = "stateDiagram-v2 LR\nIdle-->Active"
      diagram = parser.parse(source)

      expect(diagram.direction).to eq('LR')
    end

    it 'parses multiple transitions in sequence' do
      source = "stateDiagram-v2\nA-->B-->C"
      diagram = parser.parse(source)

      expect(diagram.states.length).to eq(3)
      expect(diagram.transitions.length).to eq(2)

      trans1 = diagram.transitions[0]
      expect(trans1.from_id).to eq('A')
      expect(trans1.to_id).to eq('B')

      trans2 = diagram.transitions[1]
      expect(trans2.from_id).to eq('B')
      expect(trans2.to_id).to eq('C')
    end

    it 'raises ParseError for invalid syntax' do
      source = 'invalid syntax'
      expect { parser.parse(source) }.to raise_error(
        Sirena::Parser::ParseError
      )
    end
  end
end
