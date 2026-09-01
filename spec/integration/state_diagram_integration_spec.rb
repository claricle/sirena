# frozen_string_literal: true

require 'spec_helper'
require 'rexml/document'
require 'yaml'

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

    it 'renders one described marker state in either declaration order' do
      sources = [
        "stateDiagram-v2\nstate C <<choice>>\n" \
          "C : FIRST\nC : SECOND\n",
        "stateDiagram-v2\nC : FIRST\nstate C <<choice>>\n" \
          "C : SECOND\n"
      ]

      sources.each do |source|
        diagram = parser.parse(source)
        states = diagram.states.select { |state| state.id == 'C' }
        expect(states.length).to eq(1)
        expect(states.first.state_type).to eq('choice')
        expect(states.first.description).to eq('SECOND')
        expect(states.first.descriptions).to eq(%w[FIRST SECOND])

        document = REXML::Document.new(Sirena::Engine.new.render(source))
        groups = REXML::XPath.match(document, "//*[@id='state-C']")
        expect(groups.length).to eq(1)
        expect(REXML::XPath.match(groups.first, 'rect').length).to eq(1)
        expect(REXML::XPath.match(groups.first, 'polygon')).to be_empty
        expect(REXML::XPath.match(groups.first, 'text').map(&:text))
          .to eq(%w[FIRST SECOND])
      end
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
      source = "stateDiagram-v2\ndirection LR\nIdle-->Active"

      diagram = parser.parse(source)
      expect(diagram.direction).to eq('LR')

      graph = transform.to_graph(diagram)
      expect(graph[:layoutOptions]['elk.direction']).to eq('RIGHT')
    end

    it 'requires direction statements to start below the header' do
      engine = Sirena::Engine.new

      expect { engine.render('stateDiagram-v2 direction LR') }
        .to raise_error(Sirena::Engine::PipelineError, /Parse error/)

      document = REXML::Document.new(
        engine.render("stateDiagram-v2\ndirection LR\nA --> B\n")
      )
      expect(REXML::XPath.match(document, '//text').map(&:text)).to eq(%w[A B])
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

  # The regression net for the corpus burndown: every state case mmdc
  # 11.12.0 renders has to survive the whole Engine path and come back as
  # SVG a parser accepts.
  describe 'the oracle-valid corpus' do
    def self.oracle_valid_cases
      verdicts = YAML.load_file('spec/mermaid/corpus-verdicts.yml')
        .to_h { |row| [row['case'], row['verdict']] }

      %w[state state_diagram].flat_map do |type|
        Dir.glob("spec/mermaid/#{type}/*.mmd").select do |path|
          verdicts[path.delete_prefix('spec/mermaid/')] == 'valid'
        end
      end.sort
    end

    # A tripwire, not a behaviour spec: it fails when the corpus or the
    # verdicts move, so the generated list below cannot quietly shrink.
    it 'still finds the 52 cases the examples below were generated from' do
      expect(self.class.oracle_valid_cases.length).to eq(52)
    end

    oracle_valid_cases.each do |path|
      it "renders #{path.delete_prefix('spec/mermaid/')}" do
        svg = Sirena::Engine.new.render(File.read(path))

        expect(svg).to start_with('<svg')
        expect { REXML::Document.new(svg) }.not_to raise_error
      end
    end
  end
end
