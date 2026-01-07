# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::Renderer::RequirementRenderer do
  let(:renderer) { described_class.new }

  describe '#render' do
    context 'with basic requirement diagram layout' do
      let(:layout) do
        {
          requirements: {
            'test_req' => {
              requirement: double(
                name: 'test_req',
                type: 'requirement',
                id: '1',
                text: 'the test text.',
                risk: 'high',
                verifymethod: 'test',
                classes: []
              ),
              x: 100,
              y: 100,
              width: 180,
              height: 140,
              level: 1
            }
          },
          elements: {
            'test_entity' => {
              element: double(
                name: 'test_entity',
                type: 'simulation',
                docref: nil,
                classes: []
              ),
              x: 100,
              y: 300,
              width: 150,
              height: 80,
              level: 0
            }
          },
          relationships: [
            {
              relationship: double(source: 'test_entity', target: 'test_req', type: 'satisfies'),
              source: 'test_entity',
              target: 'test_req',
              type: 'satisfies',
              from_x: 175,
              from_y: 380,
              to_x: 190,
              to_y: 240
            }
          ],
          width: 500,
          height: 500
        }
      end

      it 'renders an SVG document' do
        result = renderer.render(layout)

        expect(result).to be_a(Sirena::Svg::Document)
        expect(result.width).to eq(500)
        expect(result.height).to eq(500)
      end

      it 'renders requirements' do
        result = renderer.render(layout)

        # Check that requirement group is created
        requirement_groups = result.children.select do |child|
          child.is_a?(Sirena::Svg::Group) && child.id&.start_with?('requirement-')
        end

        expect(requirement_groups).not_to be_empty
      end

      it 'renders elements' do
        result = renderer.render(layout)

        # Check that element group is created
        element_groups = result.children.select do |child|
          child.is_a?(Sirena::Svg::Group) && child.id&.start_with?('element-')
        end

        expect(element_groups).not_to be_empty
      end

      it 'renders relationships' do
        result = renderer.render(layout)

        # Check that relationship group is created
        relationship_groups = result.children.select do |child|
          child.is_a?(Sirena::Svg::Group) && child.id&.start_with?('relationship-')
        end

        expect(relationship_groups).not_to be_empty
      end
    end

    context 'with empty layout' do
      let(:layout) do
        {
          requirements: {},
          elements: {},
          relationships: [],
          width: 400,
          height: 300
        }
      end

      it 'renders an empty SVG document' do
        result = renderer.render(layout)

        expect(result).to be_a(Sirena::Svg::Document)
        expect(result.width).to eq(400)
        expect(result.height).to eq(300)
      end
    end

    context 'with multiple requirements' do
      let(:layout) do
        {
          requirements: {
            'req1' => {
              requirement: double(
                name: 'req1',
                type: 'functionalRequirement',
                id: '1',
                text: 'First requirement',
                risk: 'low',
                verifymethod: 'test',
                classes: []
              ),
              x: 50,
              y: 50,
              width: 180,
              height: 140,
              level: 0
            },
            'req2' => {
              requirement: double(
                name: 'req2',
                type: 'performanceRequirement',
                id: '2',
                text: 'Second requirement',
                risk: 'medium',
                verifymethod: 'analysis',
                classes: []
              ),
              x: 250,
              y: 50,
              width: 180,
              height: 140,
              level: 0
            }
          },
          elements: {},
          relationships: [],
          width: 500,
          height: 300
        }
      end

      it 'renders multiple requirements' do
        result = renderer.render(layout)

        requirement_groups = result.children.select do |child|
          child.is_a?(Sirena::Svg::Group) && child.id&.start_with?('requirement-')
        end

        expect(requirement_groups.size).to eq(2)
      end
    end
  end

  describe 'risk level colors' do
    it 'uses correct colors for risk levels' do
      expect(described_class::RISK_COLORS['high']).to eq('#ff6b6b')
      expect(described_class::RISK_COLORS['medium']).to eq('#ffd93d')
      expect(described_class::RISK_COLORS['low']).to eq('#6bcf7f')
    end
  end

  describe 'requirement type labels' do
    it 'provides labels for all requirement types' do
      expect(described_class::REQUIREMENT_TYPE_LABELS['requirement']).to eq('Requirement')
      expect(described_class::REQUIREMENT_TYPE_LABELS['functionalRequirement']).to eq('Functional Req')
      expect(described_class::REQUIREMENT_TYPE_LABELS['performanceRequirement']).to eq('Performance Req')
    end
  end
end