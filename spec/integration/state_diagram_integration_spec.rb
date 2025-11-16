# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'StateDiagram Integration' do
  describe 'complete state diagram pipeline' do
    let(:parser) { Sirena::Parser::StateDiagramParser.new }
    let(:transform) { Sirena::Transform::StateDiagramTransform.new }
    let(:renderer) { Sirena::Renderer::StateDiagramRenderer.new }

    it 'parses, transforms, and renders a simple state diagram' do
      source = "stateDiagram-v2\nIdle-->Active"

      # Parse
      diagram = parser.parse(source)
      expect(diagram).to be_a(Sirena::Diagram::StateDiagram)
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

    it 'handles complete state machine with start and end' do
      source = <<~MERMAID
        stateDiagram-v2
        [*]-->Idle
        Idle-->Active: start
        Active-->[*]
      MERMAID

      diagram = parser.parse(source)

      expect(diagram.states.length).to eq(4)
      expect(diagram.start_state).not_to be_nil
      expect(diagram.end_states.length).to eq(1)
      expect(diagram.transitions.length).to eq(3)

      graph = transform.to_graph(diagram)
      svg = renderer.render(graph)

      expect(svg).to be_a(Sirena::Svg::Document)
    end

    it 'handles special state types' do
      source = <<~MERMAID
        stateDiagram-v2
        state choice1 <<choice>>
        state fork1 <<fork>>
        state join1 <<join>>
        Idle-->choice1
        choice1-->Active
      MERMAID

      diagram = parser.parse(source)

      expect(diagram.choice_states.length).to eq(1)
      expect(diagram.find_state('fork1')).not_to be_nil
      expect(diagram.find_state('join1')).not_to be_nil

      graph = transform.to_graph(diagram)
      svg = renderer.render(graph)

      expect(svg).to be_a(Sirena::Svg::Document)
    end

    it 'handles transitions with triggers and guards' do
      source = "stateDiagram-v2\nIdle-->Active: start [ready]"

      diagram = parser.parse(source)
      transition = diagram.transitions.first

      expect(transition.trigger).to eq('start')
      expect(transition.guard_condition).to eq('ready')

      graph = transform.to_graph(diagram)
      svg = renderer.render(graph)

      expect(svg).to be_a(Sirena::Svg::Document)
    end

    it 'handles different directions' do
      source = "stateDiagram-v2 LR\nIdle-->Active"

      diagram = parser.parse(source)
      expect(diagram.direction).to eq('LR')

      graph = transform.to_graph(diagram)
      expect(graph[:layoutOptions]['elk.direction']).to eq('RIGHT')
    end
  end

  describe 'DiagramRegistry integration' do
    it 'has state_diagram registered' do
      expect(
        Sirena::DiagramRegistry.registered?(:state_diagram)
      ).to be true
    end

    it 'retrieves state diagram handlers' do
      handlers = Sirena::DiagramRegistry.get(:state_diagram)

      expect(handlers).not_to be_nil
      expect(handlers[:parser]).to eq(
        Sirena::Parser::StateDiagramParser
      )
      expect(handlers[:transform]).to eq(
        Sirena::Transform::StateDiagramTransform
      )
      expect(handlers[:renderer]).to eq(
        Sirena::Renderer::StateDiagramRenderer
      )
    end
  end
end
