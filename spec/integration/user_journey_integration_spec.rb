# frozen_string_literal: true

require 'spec_helper'
require 'sirena'

RSpec.describe 'UserJourney Integration' do
  describe 'complete user journey pipeline' do
    it 'parses, transforms, and renders a simple user journey' do
      source = <<~MERMAID
        journey
          title My Journey
          section Shopping
            Browse products: 5: Customer
      MERMAID

      parser = Sirena::Parser::UserJourneyParser.new
      diagram = parser.parse(source)

      expect(diagram).to be_a(Sirena::Diagram::UserJourney)
      expect(diagram.valid?).to be true
      expect(diagram.title).to eq('My Journey')
      expect(diagram.sections.length).to eq(1)
    end

    it 'handles multiple sections and tasks' do
      source = <<~MERMAID
        journey
          title Customer Experience
          section Browse
            View homepage: 5: Customer
            Search products: 4: Customer
          section Purchase
            Add to cart: 3: Customer
            Checkout: 2: Customer, Staff
      MERMAID

      parser = Sirena::Parser::UserJourneyParser.new
      diagram = parser.parse(source)

      expect(diagram.sections.length).to eq(2)
      expect(diagram.sections[0].name).to eq('Browse')
      expect(diagram.sections[0].tasks.length).to eq(2)
      expect(diagram.sections[1].name).to eq('Purchase')
      expect(diagram.sections[1].tasks.length).to eq(2)
    end

    it 'handles tasks with multiple actors' do
      source = <<~MERMAID
        journey
          section Service
            Request support: 3: Customer, Support, Manager
      MERMAID

      parser = Sirena::Parser::UserJourneyParser.new
      diagram = parser.parse(source)

      task = diagram.sections.first.tasks.first
      expect(task.actors).to eq(%w[Customer Support Manager])
    end

    it 'handles different score values' do
      source = <<~MERMAID
        journey
          section Ratings
            Low: 1: User
            Medium: 3: User
            High: 5: User
      MERMAID

      parser = Sirena::Parser::UserJourneyParser.new
      diagram = parser.parse(source)

      tasks = diagram.sections.first.tasks
      expect(tasks[0].score).to eq(1)
      expect(tasks[0].score_color).to eq(:red)
      expect(tasks[1].score).to eq(3)
      expect(tasks[1].score_color).to eq(:yellow)
      expect(tasks[2].score).to eq(5)
      expect(tasks[2].score_color).to eq(:green)
    end
  end

  describe 'DiagramRegistry integration' do
    it 'has user_journey registered' do
      expect(Sirena::DiagramRegistry.registered?(:user_journey))
        .to be true
    end

    it 'retrieves user journey handlers' do
      handlers = Sirena::DiagramRegistry.get(:user_journey)

      expect(handlers).not_to be_nil
      expect(handlers[:parser])
        .to eq(Sirena::Parser::UserJourneyParser)
      expect(handlers[:transform])
        .to eq(Sirena::Transform::UserJourneyTransform)
      expect(handlers[:renderer])
        .to eq(Sirena::Renderer::UserJourneyRenderer)
    end
  end
end
