# frozen_string_literal: true

require 'spec_helper'
require 'sirena/transform/user_journey'
require 'sirena/diagram/user_journey'

RSpec.describe Sirena::Transform::UserJourneyTransform do
  let(:transform) { described_class.new }

  describe '#to_graph' do
    it 'converts diagram to graph structure' do
      diagram = Sirena::Diagram::UserJourney.new.tap do |d|
        d.title = 'My Journey'
        section = Sirena::Diagram::JourneySection.new.tap do |s|
          s.name = 'Shopping'
          s.tasks << Sirena::Diagram::JourneyTask.new.tap do |t|
            t.name = 'Browse'
            t.score = 5
            t.actors = ['Customer']
          end
        end
        d.sections << section
      end

      graph = transform.to_graph(diagram)

      expect(graph).to be_a(Hash)
      expect(graph[:id]).to eq('user_journey')
      expect(graph[:children]).to be_a(Array)
      expect(graph[:edges]).to be_a(Array)
      expect(graph[:layoutOptions]).to be_a(Hash)
    end

    it 'creates task nodes with dimensions' do
      diagram = Sirena::Diagram::UserJourney.new.tap do |d|
        section = Sirena::Diagram::JourneySection.new.tap do |s|
          s.name = 'Shopping'
          s.tasks << Sirena::Diagram::JourneyTask.new.tap do |t|
            t.name = 'Browse'
            t.score = 5
            t.actors = ['Customer']
          end
        end
        d.sections << section
      end

      graph = transform.to_graph(diagram)

      expect(graph[:children].length).to eq(1)
      node = graph[:children].first
      expect(node[:id]).to eq('task_0')
      expect(node[:width]).to be > 0
      expect(node[:height]).to be > 0
    end

    it 'creates sequential edges between tasks' do
      diagram = Sirena::Diagram::UserJourney.new.tap do |d|
        section = Sirena::Diagram::JourneySection.new.tap do |s|
          s.name = 'Shopping'
          s.tasks << Sirena::Diagram::JourneyTask.new.tap do |t|
            t.name = 'Browse'
            t.score = 5
            t.actors = ['Customer']
          end
          s.tasks << Sirena::Diagram::JourneyTask.new.tap do |t|
            t.name = 'Select'
            t.score = 4
            t.actors = ['Customer']
          end
        end
        d.sections << section
      end

      graph = transform.to_graph(diagram)

      expect(graph[:edges].length).to eq(1)
      edge = graph[:edges].first
      expect(edge[:sources]).to eq(['task_0'])
      expect(edge[:targets]).to eq(['task_1'])
    end

    it 'includes task metadata' do
      diagram = Sirena::Diagram::UserJourney.new.tap do |d|
        section = Sirena::Diagram::JourneySection.new.tap do |s|
          s.name = 'Shopping'
          s.tasks << Sirena::Diagram::JourneyTask.new.tap do |t|
            t.name = 'Browse'
            t.score = 5
            t.actors = ['Customer']
          end
        end
        d.sections << section
      end

      graph = transform.to_graph(diagram)

      node = graph[:children].first
      expect(node[:metadata][:name]).to eq('Browse')
      expect(node[:metadata][:score]).to eq(5)
      expect(node[:metadata][:actors]).to eq(['Customer'])
      expect(node[:metadata][:section_name]).to eq('Shopping')
    end

    it 'sets horizontal layout options' do
      diagram = Sirena::Diagram::UserJourney.new.tap do |d|
        section = Sirena::Diagram::JourneySection.new.tap do |s|
          s.name = 'Shopping'
          s.tasks << Sirena::Diagram::JourneyTask.new.tap do |t|
            t.name = 'Browse'
            t.score = 5
            t.actors = ['Customer']
          end
        end
        d.sections << section
      end

      graph = transform.to_graph(diagram)

      expect(graph[:layoutOptions]['elk.direction']).to eq('RIGHT')
    end

    it 'raises error for invalid diagram' do
      diagram = Sirena::Diagram::UserJourney.new

      expect { transform.to_graph(diagram) }.to raise_error(
        Sirena::Transform::TransformError
      )
    end
  end
end
