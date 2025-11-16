# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::Transform::ClassDiagramTransform do
  let(:transform) { described_class.new }

  describe '#to_graph' do
    let(:diagram) do
      Sirena::Diagram::ClassDiagram.new(direction: 'TB').tap do |d|
        d.entities << Sirena::Diagram::ClassEntity.new(
          id: 'Animal',
          name: 'Animal'
        ).tap do |entity|
          entity.attributes << Sirena::Diagram::ClassAttribute.new(
            name: 'age',
            type: 'int',
            visibility: 'protected'
          )
          entity.class_methods << Sirena::Diagram::ClassMethod.new(
            name: 'breathe',
            visibility: 'public'
          )
        end
        d.entities << Sirena::Diagram::ClassEntity.new(
          id: 'Dog',
          name: 'Dog'
        ).tap do |entity|
          entity.class_methods << Sirena::Diagram::ClassMethod.new(
            name: 'bark',
            visibility: 'public'
          )
        end
        d.relationships << Sirena::Diagram::ClassRelationship.new(
          from_id: 'Dog',
          to_id: 'Animal',
          relationship_type: 'inheritance'
        )
      end
    end

    it 'converts diagram to graph structure' do
      graph = transform.to_graph(diagram)

      expect(graph).to be_a(Hash)
      expect(graph[:id]).to eq('class_diagram')
      expect(graph[:children]).to be_an(Array)
      expect(graph[:edges]).to be_an(Array)
      expect(graph[:layoutOptions]).to be_a(Hash)
    end

    it 'creates entities with dimensions' do
      graph = transform.to_graph(diagram)

      expect(graph[:children].length).to eq(2)

      animal = graph[:children].find { |n| n[:id] == 'Animal' }
      expect(animal).not_to be_nil
      expect(animal[:width]).to be > 0
      expect(animal[:height]).to be > 0
      expect(animal[:metadata][:name]).to eq('Animal')
      expect(animal[:metadata][:attributes]).to be_an(Array)
      expect(animal[:metadata][:methods]).to be_an(Array)
    end

    it 'includes attributes metadata' do
      graph = transform.to_graph(diagram)

      animal = graph[:children].find { |n| n[:id] == 'Animal' }
      attributes = animal[:metadata][:attributes]

      expect(attributes.length).to eq(1)
      expect(attributes.first[:name]).to eq('age')
      expect(attributes.first[:type]).to eq('int')
      expect(attributes.first[:visibility]).to eq('protected')
    end

    it 'includes methods metadata' do
      graph = transform.to_graph(diagram)

      animal = graph[:children].find { |n| n[:id] == 'Animal' }
      methods = animal[:metadata][:methods]

      expect(methods.length).to eq(1)
      expect(methods.first[:name]).to eq('breathe')
      expect(methods.first[:visibility]).to eq('public')
    end

    it 'creates relationships with metadata' do
      graph = transform.to_graph(diagram)

      expect(graph[:edges].length).to eq(1)

      edge = graph[:edges].first
      expect(edge[:sources]).to eq(['Dog'])
      expect(edge[:targets]).to eq(['Animal'])
      expect(edge[:metadata][:relationship_type]).to eq('inheritance')
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

    it 'handles entities with stereotypes' do
      diagram.entities.first.stereotype = 'interface'
      graph = transform.to_graph(diagram)

      animal = graph[:children].find { |n| n[:id] == 'Animal' }
      expect(animal[:metadata][:stereotype]).to eq('interface')
    end

    it 'raises error for invalid diagram' do
      invalid_diagram = Sirena::Diagram::ClassDiagram.new

      expect do
        transform.to_graph(invalid_diagram)
      end.to raise_error(Sirena::Transform::TransformError)
    end
  end
end
