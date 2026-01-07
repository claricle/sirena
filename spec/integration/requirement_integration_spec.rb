# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Requirement Integration' do
  describe 'complete requirement pipeline' do
    let(:parser) { Sirena::Parser::RequirementParser.new }
    let(:transform) { Sirena::Transform::RequirementTransform.new }
    let(:renderer) { Sirena::Renderer::RequirementRenderer.new }

    it 'parses, transforms, and renders a simple requirement diagram' do
      source = <<~MERMAID
        requirementDiagram

            requirement test_req {
            id: 1
            text: the test text.
            risk: high
            verifymethod: test
            }

            element test_entity {
            type: simulation
            }

            test_entity - satisfies -> test_req
      MERMAID

      # Parse
      diagram = parser.parse(source)
      expect(diagram).to be_a(Sirena::Diagram::RequirementDiagram)
      expect(diagram.requirements.length).to eq(1)
      expect(diagram.elements.length).to eq(1)
      expect(diagram.relationships.length).to eq(1)

      # Verify requirement
      req = diagram.requirements.first
      expect(req.name).to eq('test_req')
      expect(req.id).to eq('1')
      expect(req.text).to eq('the test text.')
      expect(req.risk).to eq('high')
      expect(req.verifymethod).to eq('test')

      # Verify element
      elem = diagram.elements.first
      expect(elem.name).to eq('test_entity')
      expect(elem.type).to eq('simulation')

      # Verify relationship
      rel = diagram.relationships.first
      expect(rel.source).to eq('test_entity')
      expect(rel.target).to eq('test_req')
      expect(rel.type).to eq('satisfies')

      # Transform
      graph = transform.to_graph(diagram)
      expect(graph).to be_a(Hash)
      expect(graph[:requirements].length).to eq(1)
      expect(graph[:elements].length).to eq(1)
      expect(graph[:relationships].length).to eq(1)

      # Render
      svg = renderer.render(graph)
      expect(svg).to be_a(Sirena::Svg::Document)
      expect(svg.children).not_to be_empty
    end

    it 'handles multiple requirement types' do
      source = <<~MERMAID
        requirementDiagram

            functionalRequirement func_req {
            id: F1
            text: System must handle user login
            risk: medium
            verifymethod: test
            }

            performanceRequirement perf_req {
            id: P1
            text: Response time under 2 seconds
            risk: high
            verifymethod: demonstration
            }
      MERMAID

      diagram = parser.parse(source)
      expect(diagram.requirements.length).to eq(2)

      func_req = diagram.requirements.find { |r| r.name == 'func_req' }
      expect(func_req.type).to eq('functionalRequirement')

      perf_req = diagram.requirements.find { |r| r.name == 'perf_req' }
      expect(perf_req.type).to eq('performanceRequirement')

      graph = transform.to_graph(diagram)
      svg = renderer.render(graph)

      expect(svg).to be_a(Sirena::Svg::Document)
    end

    it 'handles all relationship types' do
      source = <<~MERMAID
        requirementDiagram

            requirement req1 {
            id: 1
            text: Base requirement
            }

            requirement req2 {
            id: 2
            text: Derived requirement
            }

            element elem1 {
            type: component
            }

            req1 - contains -> req2
            req2 - satisfies -> elem1
      MERMAID

      diagram = parser.parse(source)
      expect(diagram.relationships.length).to eq(2)

      contains_rel = diagram.relationships.find { |r| r.type == 'contains' }
      expect(contains_rel).not_to be_nil
      expect(contains_rel.source).to eq('req1')
      expect(contains_rel.target).to eq('req2')

      satisfies_rel = diagram.relationships.find { |r| r.type == 'satisfies' }
      expect(satisfies_rel).not_to be_nil
      expect(satisfies_rel.source).to eq('req2')
      expect(satisfies_rel.target).to eq('elem1')
    end

    it 'handles styling directives' do
      source = <<~MERMAID
        requirementDiagram

            requirement test_req {
            id: 1
            text: Test requirement
            }

            style test_req fill:#f9f,stroke:#333,stroke-width:4px
      MERMAID

      diagram = parser.parse(source)
      expect(diagram.styles.length).to eq(1)

      style = diagram.styles.first
      expect(style.target_ids).to include('test_req')
      expect(style.fill).to eq('#f9f')
      expect(style.stroke).to eq('#333')
      expect(style.stroke_width).to eq('4px')
    end

    it 'handles class definitions and assignments' do
      source = <<~MERMAID
        requirementDiagram

            requirement req1 {
            id: 1
            text: Test
            }

            classDef critical fill:#ff0000

            class req1 critical
      MERMAID

      diagram = parser.parse(source)
      expect(diagram.classes.length).to eq(1)
      expect(diagram.class_assignments.length).to eq(1)

      klass = diagram.classes.first
      expect(klass.name).to eq('critical')
      expect(klass.fill).to eq('#ff0000')

      assignment = diagram.class_assignments.first
      expect(assignment.target_ids).to include('req1')
      expect(assignment.class_names).to include('critical')
    end
  end

  describe 'DiagramRegistry integration' do
    it 'has requirement registered' do
      expect(Sirena::DiagramRegistry.registered?(:requirement)).to be true
    end

    it 'retrieves requirement handlers' do
      handlers = Sirena::DiagramRegistry.get(:requirement)

      expect(handlers).not_to be_nil
      expect(handlers[:parser]).to eq(Sirena::Parser::RequirementParser)
      expect(handlers[:transform]).to eq(
        Sirena::Transform::RequirementTransform
      )
      expect(handlers[:renderer]).to eq(
        Sirena::Renderer::RequirementRenderer
      )
    end
  end
end