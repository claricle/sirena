# frozen_string_literal: true

require "spec_helper"
require "sirena"

RSpec.describe Sirena::Parser::UserJourney, :aggregate_failures do
  describe "complete user journey pipeline" do
    let(:diagram) { described_class.new.parse(source) }

    context "with a simple user journey" do
      let(:source) do
        <<~MERMAID
          journey
            title My Journey
            section Shopping
              Browse products: 5: Customer
        MERMAID
      end

      it "parses a valid UserJourney" do
        expect(diagram).to be_a(Sirena::Diagram::UserJourney)
        expect(diagram.valid?).to be true
      end

      it "parses the title and section" do
        expect(diagram.title).to eq("My Journey")
        expect(diagram.sections.length).to eq(1)
      end
    end

    context "with multiple sections and tasks" do
      let(:source) do
        <<~MERMAID
          journey
            title Customer Experience
            section Browse
              View homepage: 5: Customer
              Search products: 4: Customer
            section Purchase
              Add to cart: 3: Customer
              Checkout: 2: Customer, Staff
        MERMAID
      end

      it "parses both sections" do
        expect(diagram.sections.length).to eq(2)
      end

      it "parses the Browse section's name and tasks" do
        expect(diagram.sections[0].name).to eq("Browse")
        expect(diagram.sections[0].tasks.length).to eq(2)
      end

      it "parses the Purchase section's name and tasks" do
        expect(diagram.sections[1].name).to eq("Purchase")
        expect(diagram.sections[1].tasks.length).to eq(2)
      end
    end

    context "with a task with multiple actors" do
      let(:source) do
        <<~MERMAID
          journey
            section Service
              Request support: 3: Customer, Support, Manager
        MERMAID
      end

      it "parses every actor in order" do
        task = diagram.sections.first.tasks.first

        expect(task.actors).to eq(%w[Customer Support Manager])
      end
    end

    context "with different score values" do
      let(:source) do
        <<~MERMAID
          journey
            section Ratings
              Low: 1: User
              Medium: 3: User
              High: 5: User
        MERMAID
      end
      let(:tasks) { diagram.sections.first.tasks }

      it "parses each score" do
        expect(tasks.map(&:score)).to eq([1, 3, 5])
      end

      it "colours each score" do
        expect(tasks.map(&:score_color)).to eq(%i[red yellow green])
      end
    end
  end

  describe "journeys with no sections" do
    # Corpus burndown TODO.foundation/07d: mmdc renders a bare `journey`
    # (with or without a title) rather than rejecting it, so the full
    # pipeline must render one too instead of raising LayoutError.
    {
      "003/007: journey with a title, no sections" => <<~MERMAID,
        journey
        title Adding journey diagram functionality to mermaid
      MERMAID
      "014/015/024/025: journey with nothing else" => "journey\n",
    }.each do |description, source|
      it "renders #{description}" do
        svg = Sirena::Engine.new.render(source)

        expect(svg).to include("<svg")
        expect(svg).to include("</svg>")
      end
    end
  end

  describe "DiagramRegistry integration" do
    it "has user_journey registered" do
      expect(Sirena::DiagramRegistry.registered?(:user_journey))
        .to be true
    end

    it "retrieves user journey handlers" do
      handlers = Sirena::DiagramRegistry.get(:user_journey)

      expect(handlers).not_to be_nil
      expect(handlers[:parser]).to eq(described_class)
      expect(handlers[:transform]).to eq(Sirena::Layout::UserJourney)
      expect(handlers[:renderer]).to eq(Sirena::Renderer::UserJourney)
    end
  end
end
