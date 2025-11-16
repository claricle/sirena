# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::Parser::RequirementParser do
  let(:parser) { described_class.new }

  describe '#parse' do
    context 'with basic requirement diagram' do
      let(:source) do
        <<~MERMAID
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
      end

      it 'parses the diagram successfully' do
        result = parser.parse(source)

        expect(result).to be_a(Sirena::Diagram::RequirementDiagram)
        expect(result.requirements.size).to eq(1)
        expect(result.elements.size).to eq(1)
        expect(result.relationships.size).to eq(1)
      end

      it 'parses requirement properties correctly' do
        result = parser.parse(source)
        req = result.requirements.first

        expect(req.name).to eq('test_req')
        expect(req.type).to eq('requirement')
        expect(req.id).to eq('1')
        expect(req.text).to eq('the test text.')
        expect(req.risk).to eq('high')
        expect(req.verifymethod).to eq('test')
      end

      it 'parses element properties correctly' do
        result = parser.parse(source)
        elem = result.elements.first

        expect(elem.name).to eq('test_entity')
        expect(elem.type).to eq('simulation')
      end

      it 'parses relationships correctly' do
        result = parser.parse(source)
        rel = result.relationships.first

        expect(rel.source).to eq('test_entity')
        expect(rel.target).to eq('test_req')
        expect(rel.type).to eq('satisfies')
      end
    end

    context 'with empty diagram' do
      let(:source) { "requirementDiagram\n" }

      it 'parses successfully' do
        result = parser.parse(source)

        expect(result).to be_a(Sirena::Diagram::RequirementDiagram)
        expect(result.requirements).to be_empty
        expect(result.elements).to be_empty
        expect(result.relationships).to be_empty
      end
    end

    context 'with multiple requirement types' do
      let(:source) do
        <<~MERMAID
          requirementDiagram

              functionalRequirement func_req {
              id: 1
              text: functional requirement
              }

              performanceRequirement perf_req {
              id: 2
              text: performance requirement
              }
        MERMAID
      end

      it 'parses different requirement types' do
        result = parser.parse(source)

        expect(result.requirements.size).to eq(2)
        expect(result.requirements[0].type).to eq('functionalRequirement')
        expect(result.requirements[1].type).to eq('performanceRequirement')
      end
    end

    context 'with all relationship types' do
      let(:source) do
        <<~MERMAID
          requirementDiagram

              requirement req1 {
              id: 1
              }

              requirement req2 {
              id: 2
              }

              element elem1 {
              type: test
              }

              req1 - contains -> req2
              req1 - copies -> req2
              req1 - derives -> req2
              elem1 - satisfies -> req1
              elem1 - verifies -> req1
              req2 - refines -> req1
              req2 - traces -> req1
        MERMAID
      end

      it 'parses all relationship types' do
        result = parser.parse(source)

        expect(result.relationships.size).to eq(7)

        types = result.relationships.map(&:type)
        expect(types).to include('contains', 'copies', 'derives', 'satisfies', 'verifies', 'refines', 'traces')
      end
    end

    context 'with styling' do
      let(:source) do
        <<~MERMAID
          requirementDiagram

              requirement req1 {
              id: 1
              }

              style req1 fill:#f9f,stroke:#333
        MERMAID
      end

      it 'parses styling directives' do
        result = parser.parse(source)

        expect(result.styles.size).to eq(1)
        style = result.styles.first
        expect(style.fill).to eq('#f9f')
        expect(style.stroke).to eq('#333')
      end
    end

    context 'with class definitions' do
      let(:source) do
        <<~MERMAID
          requirementDiagram

              requirement req1 {
              id: 1
              }

              classDef myClass fill:#f96
              class req1 myClass
        MERMAID
      end

      it 'parses class definitions and assignments' do
        result = parser.parse(source)

        expect(result.classes.size).to eq(1)
        expect(result.class_assignments.size).to eq(1)

        klass = result.classes.first
        expect(klass.name).to eq('myClass')
        expect(klass.fill).to eq('#f96')
      end
    end
  end
end