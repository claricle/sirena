# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::Transform::ErDiagramTransform do
  let(:transform) { described_class.new }

  describe '#to_graph' do
    let(:diagram) do
      Sirena::Diagram::ErDiagram.new.tap do |d|
        d.entities << Sirena::Diagram::ErEntity.new(
          id: 'CUSTOMER',
          name: 'CUSTOMER'
        ).tap do |entity|
          entity.attributes << Sirena::Diagram::ErAttribute.new(
            name: 'id',
            attribute_type: 'int',
            key_type: 'PK'
          )
          entity.attributes << Sirena::Diagram::ErAttribute.new(
            name: 'name',
            attribute_type: 'string'
          )
        end
        d.entities << Sirena::Diagram::ErEntity.new(
          id: 'ORDER',
          name: 'ORDER'
        )
        d.relationships << Sirena::Diagram::ErRelationship.new(
          from_id: 'CUSTOMER',
          to_id: 'ORDER',
          relationship_type: 'non-identifying',
          cardinality_from: 'one',
          cardinality_to: 'zero_or_more',
          label: 'places'
        )
      end
    end

    it 'converts diagram to graph structure' do
      graph = transform.to_graph(diagram)

      expect(graph).to be_a(Hash)
      expect(graph[:id]).to eq('er_diagram')
      expect(graph[:children]).to be_an(Array)
      expect(graph[:edges]).to be_an(Array)
      expect(graph[:layoutOptions]).to be_a(Hash)
    end

    it 'creates entities with dimensions' do
      graph = transform.to_graph(diagram)

      expect(graph[:children].length).to eq(2)

      customer = graph[:children].find { |n| n[:id] == 'CUSTOMER' }
      expect(customer).not_to be_nil
      expect(customer[:width]).to be > 0
      expect(customer[:height]).to be > 0
      expect(customer[:metadata][:name]).to eq('CUSTOMER')
      expect(customer[:metadata][:attributes]).to be_an(Array)
    end

    it 'includes attributes metadata' do
      graph = transform.to_graph(diagram)

      customer = graph[:children].find { |n| n[:id] == 'CUSTOMER' }
      attributes = customer[:metadata][:attributes]

      expect(attributes.length).to eq(2)
      expect(attributes.first[:name]).to eq('id')
      expect(attributes.first[:attribute_type]).to eq('int')
      expect(attributes.first[:key_type]).to eq('PK')
    end

    it 'creates relationships with metadata' do
      graph = transform.to_graph(diagram)

      expect(graph[:edges].length).to eq(1)

      edge = graph[:edges].first
      expect(edge[:sources]).to eq(['CUSTOMER'])
      expect(edge[:targets]).to eq(['ORDER'])
      expect(edge[:metadata][:relationship_type]).to eq('non-identifying')
      expect(edge[:metadata][:cardinality_from]).to eq('one')
      expect(edge[:metadata][:cardinality_to]).to eq('zero_or_more')
    end

    it 'includes relationship label' do
      graph = transform.to_graph(diagram)

      edge = graph[:edges].first
      labels = edge[:labels]

      expect(labels).to be_an(Array)
      label = labels.find { |l| l[:text] == 'places' }
      expect(label).not_to be_nil
    end

    it 'sets layout options for ER diagrams' do
      graph = transform.to_graph(diagram)

      options = graph[:layoutOptions]
      expect(options['algorithm']).to eq('layered')
      expect(options['elk.direction']).to eq('RIGHT')
    end

    it 'raises error for invalid diagram' do
      invalid_diagram = Sirena::Diagram::ErDiagram.new

      expect do
        transform.to_graph(invalid_diagram)
      end.to raise_error(Sirena::Transform::TransformError)
    end
  end
end
