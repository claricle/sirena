# frozen_string_literal: true

require 'spec_helper'
require 'sirena/parser/user_journey'

RSpec.describe Sirena::Parser::UserJourneyParser do
  let(:parser) { described_class.new }

  describe '#parse' do
    it 'parses simple user journey with one task' do
      source = <<~MERMAID
        journey
          title My Journey
          section Shopping
            Browse products: 5: Customer
      MERMAID

      diagram = parser.parse(source)

      expect(diagram).to be_a(Sirena::Diagram::UserJourney)
      expect(diagram.title).to eq('My Journey')
      expect(diagram.sections.length).to eq(1)
      expect(diagram.sections.first.name).to eq('Shopping')
      expect(diagram.sections.first.tasks.length).to eq(1)
      expect(diagram.sections.first.tasks.first.name).to eq('Browse products')
      expect(diagram.sections.first.tasks.first.score).to eq(5)
      expect(diagram.sections.first.tasks.first.actors).to eq(['Customer'])
    end

    it 'parses user journey without title' do
      source = <<~MERMAID
        journey
          section Shopping
            Browse: 5: Customer
      MERMAID

      diagram = parser.parse(source)

      expect(diagram.title).to be_nil
      expect(diagram.sections.length).to eq(1)
    end

    it 'parses multiple sections' do
      source = <<~MERMAID
        journey
          section Shopping
            Browse: 5: Customer
          section Checkout
            Pay: 3: Customer
      MERMAID

      diagram = parser.parse(source)

      expect(diagram.sections.length).to eq(2)
      expect(diagram.sections[0].name).to eq('Shopping')
      expect(diagram.sections[1].name).to eq('Checkout')
    end

    it 'parses multiple tasks in a section' do
      source = <<~MERMAID
        journey
          section Shopping
            Browse: 5: Customer
            Select: 4: Customer
            Add to cart: 4: Customer
      MERMAID

      diagram = parser.parse(source)

      expect(diagram.sections.first.tasks.length).to eq(3)
      expect(diagram.sections.first.tasks[0].name).to eq('Browse')
      expect(diagram.sections.first.tasks[1].name).to eq('Select')
      expect(diagram.sections.first.tasks[2].name).to eq('Add to cart')
    end

    it 'parses tasks with multiple actors' do
      source = <<~MERMAID
        journey
          section Shopping
            Checkout: 3: Customer, Staff
      MERMAID

      diagram = parser.parse(source)

      task = diagram.sections.first.tasks.first
      expect(task.actors).to eq(%w[Customer Staff])
    end

    it 'parses tasks with different scores' do
      source = <<~MERMAID
        journey
          section Test
            Task1: 1: Actor
            Task2: 2: Actor
            Task3: 3: Actor
            Task4: 4: Actor
            Task5: 5: Actor
      MERMAID

      diagram = parser.parse(source)

      tasks = diagram.sections.first.tasks
      expect(tasks[0].score).to eq(1)
      expect(tasks[1].score).to eq(2)
      expect(tasks[2].score).to eq(3)
      expect(tasks[3].score).to eq(4)
      expect(tasks[4].score).to eq(5)
    end

    it 'raises ParseError for invalid syntax' do
      source = 'invalid'

      expect { parser.parse(source) }.to raise_error(
        Sirena::Parser::ParseError
      )
    end

    it 'raises ParseError for score out of range' do
      source = <<~MERMAID
        journey
          section Test
            Task: 6: Actor
      MERMAID

      expect { parser.parse(source) }.to raise_error(
        Sirena::Parser::ParseError,
        /Score must be between 1 and 5/
      )
    end
  end
end
