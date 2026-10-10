# frozen_string_literal: true

require "spec_helper"
require "sirena/diagram/user_journey"

RSpec.describe Sirena::Diagram::UserJourney do
  def task(name, actors, score = 3)
    Sirena::Diagram::JourneyTask.new(
      name: name, actors: actors, score: score,
    )
  end

  def journey_with(*tasks)
    section = Sirena::Diagram::JourneySection.new(name: "Visit", tasks: tasks)
    described_class.new(sections: [section])
  end

  it "filters tasks by actor without duplicating multi-actor tasks" do
    shared = task("Browse", %w[Customer Staff])
    customer = task("Buy", ["Customer"], 5)
    journey = journey_with(shared, customer, task("Stock", ["Staff"]))
    expect(journey.tasks_by_actor("Customer")).to eq([shared, customer])
  end

  it "returns no tasks for an actor absent from the journey" do
    journey = journey_with(task("Browse", ["Customer"]))

    expect(journey.tasks_by_actor("Unknown")).to eq([])
  end

  describe Sirena::Diagram::JourneyTask do
    it "rejects an explicitly missing actor collection" do
      item = described_class.new(name: "Browse", score: 4, actors: nil)

      expect(item).not_to be_valid
    end
  end

  describe Sirena::Diagram::JourneySection do
    it "rejects a named section containing an invalid task" do
      invalid = Sirena::Diagram::JourneyTask.new(name: "Browse", score: 6)
      section = described_class.new(name: "Visit", tasks: [invalid])

      expect(section).not_to be_valid
    end
  end
end
