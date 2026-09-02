# frozen_string_literal: true

require 'spec_helper'
require 'rexml/document'
require 'yaml'

RSpec.describe 'StateDiagram Integration' do
  def rendered_state(source, state_id)
    document = REXML::Document.new(Sirena::Engine.new.render(source))
    REXML::XPath.first(document, "//*[@id='state-#{state_id}']")
  end

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

    it 'renders one described state while preserving its first established type' do
      cases = [
        ["stateDiagram-v2\nstate C <<choice>>\n" \
         "C : FIRST\nC : SECOND\n", 'choice'],
        ["stateDiagram-v2\nC : FIRST\nstate C <<choice>>\n" \
         "C : SECOND\n", 'normal']
      ]

      cases.each do |source, expected_type|
        diagram = parser.parse(source)
        states = diagram.states.select { |state| state.id == 'C' }
        expect(states.length).to eq(1)
        expect(states.first.state_type).to eq(expected_type)
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

    # mmdc 11.12.0 exits 1 with no output on every separator width, including
    # none at all: `stateDiagram-v2direction LR` is not a diagram. The first
    # guard here required one space, so the zero-space form walked past it.
    it 'refuses a direction on the header line at any separator width' do
      engine = Sirena::Engine.new

      ["stateDiagram-v2direction LR\nA --> B\n",
       "stateDiagram-v2 direction LR\nA --> B\n",
       "stateDiagram-v2\tdirection LR\nA --> B\n"].each do |source|
        expect { engine.render(source) }
          .to raise_error(Sirena::Engine::PipelineError, /Parse error/), source
      end
    end
  end

  describe 'marker states that carry display text' do
    let(:parser) { Sirena::Parser::StateDiagramParser.new }

    # An alias is stored in `descriptions`, never in the scalar `description`,
    # so it coerces either established type to a rectangle at render time.
    it 'draws an aliased state as a rectangle while preserving its first type' do
      engine = Sirena::Engine.new

      [["stateDiagram-v2\nstate C <<choice>>\nstate \"Label\" as C\n", 'choice'],
       ["stateDiagram-v2\nstate \"Label\" as C\nstate C <<choice>>\n", 'normal']]
        .each do |source, expected_type|
        diagram = parser.parse(source)
        svg = engine.render(source)

        expect(diagram.find_state('C').state_type).to eq(expected_type)
        expect([svg.scan('<polygon').size, svg.scan('<rect').size])
          .to eq([0, 1]), source
      end
    end

    # The guard above must not reach the label. A bare marker's label is its own
    # id, so keying the shape on display text INCLUDING the label would turn
    # every marker into a rectangle.
    it 'keeps a marker without display text as a polygon' do
      svg = Sirena::Engine.new.render("stateDiagram-v2\nstate C <<choice>>\nC --> A\n")

      expect(svg.scan('<polygon').size).to eq(1)
    end

    it 'renders the first established state type' do
      cases = [
        ["stateDiagram-v2\nC --> A\nstate C <<choice>>\n", [1, 0]],
        ["stateDiagram-v2\nstate C <<choice>>\nC --> A\n", [0, 1]],
        ["stateDiagram-v2\nstate C <<fork>>\nstate C <<choice>>\n", [1, 0]],
        ["stateDiagram-v2\nstate C <<choice>>\nstate C <<fork>>\n", [0, 1]]
      ]

      cases.each do |source, expected_shapes|
        group = rendered_state(source, 'C')
        shapes = [
          REXML::XPath.match(group, 'rect').length,
          REXML::XPath.match(group, 'polygon').length
        ]

        expect(shapes).to eq(expected_shapes), source
      end
    end

    it 'trims alias labels and ignores a whitespace-only alias' do
      labelled = rendered_state(
        "stateDiagram-v2\nstate \"  Label  \" as C\n",
        'C'
      )
      expect(REXML::XPath.match(labelled, 'text').map(&:text)).to eq(['Label'])

      choice = rendered_state(
        "stateDiagram-v2\nstate C <<choice>>\nstate \"   \" as C\n",
        'C'
      )
      expect(REXML::XPath.match(choice, 'rect')).to be_empty
      expect(REXML::XPath.match(choice, 'polygon').length).to eq(1)
      expect(REXML::XPath.match(choice, 'text').map(&:text)).to eq(['C'])
    end
  end

  describe 'state text syntax' do
    it 'rejects escaped alias quotes while rendering an ordinary alias' do
      engine = Sirena::Engine.new

      expect do
        engine.render("stateDiagram-v2\nstate \"A\\\"B\" as X\n")
      end.to raise_error(Sirena::Engine::PipelineError, /Parse error/)

      group = rendered_state("stateDiagram-v2\nstate \"AB\" as X\n", 'X')
      expect(REXML::XPath.match(group, 'text').map(&:text)).to eq(['AB'])
    end

    it 'renders a bare description through the physical line ending' do
      cases = [
        ["stateDiagram-v2\nA :   ", ['A']],
        ["stateDiagram-v2\nA : %% comment\n", ['%% comment']],
        ["stateDiagram-v2\nA : Text %% comment\n", ['Text %% comment']]
      ]

      cases.each do |source, expected_text|
        group = rendered_state(source, 'A')

        expect(REXML::XPath.match(group, 'text').map(&:text))
          .to eq(expected_text), source
      end
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

    # A count tripwire, not a behaviour spec: it catches changes to the total
    # number of oracle-valid cases represented by the generated list below.
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
