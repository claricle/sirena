# frozen_string_literal: true

require "spec_helper"
require "sirena/diagram/timeline"

RSpec.describe Sirena::Diagram::Timeline do
  describe Sirena::Diagram::TimelineEvent do
    subject(:event) do
      described_class.new(time: "2020", descriptions: ["First event"])
    end

    describe "#valid?" do
      it "accepts an event with a time and description" do
        expect(event.valid?).to be(true)
      end

      it "rejects a missing or empty time" do
        events = [nil, ""].map do |time|
          described_class.new(time: time, descriptions: ["Event"])
        end

        expect(events.map(&:valid?)).to eq([false, false])
      end

      it "rejects an event without descriptions" do
        expect(described_class.new(time: "2020").valid?).to be(false)
      end
    end

    describe "descriptions" do
      it "returns the first description as primary" do
        event.descriptions << "Second event"

        expect(event.primary_description).to eq("First event")
      end

      it "returns nil as the primary description when none exist" do
        expect(described_class.new.primary_description).to be_nil
      end

      it "reports whether more than one description exists" do
        single = described_class.new(descriptions: ["Only event"])
        multiple = described_class.new(descriptions: %w[First Second])

        expect([single.multiple_descriptions?, multiple.multiple_descriptions?])
          .to eq([false, true])
      end
    end
  end

  describe Sirena::Diagram::TimelineSection do
    subject(:section) { described_class.new("Early years") }

    describe "#valid?" do
      it "accepts a named section" do
        expect(section.valid?).to be(true)
      end

      it "rejects a missing or empty name" do
        sections = [described_class.new, described_class.new("")]

        expect(sections.map(&:valid?)).to eq([false, false])
      end
    end

    it "initializes empty event and task collections" do
      expect([section.events, section.tasks]).to eq([[], []])
    end

    it "reports events and tasks independently" do
      expect([section.has_events?, section.has_tasks?]).to eq([false, false])

      section.events << Sirena::Diagram::TimelineEvent.new
      section.tasks << "Research"

      expect([section.has_events?, section.has_tasks?]).to eq([true, true])
    end
  end

  def event(time, description)
    Sirena::Diagram::TimelineEvent.new(
      time: time,
      descriptions: [description],
    )
  end

  subject(:timeline) { described_class.new }

  it "is valid when empty and reports its diagram type" do
    expect([timeline.valid?, timeline.diagram_type]).to eq([true, :timeline])
  end

  describe "event collections" do
    let(:standalone_event) { event("2020", "Standalone") }
    let(:section_event) { event("2021", "In a section") }
    let(:section) do
      Sirena::Diagram::TimelineSection.new("Later").tap do |value|
        value.events << section_event
      end
    end

    it "detects standalone events" do
      timeline.events << standalone_event

      expect(timeline.has_events?).to be(true)
    end

    it "detects events nested in sections" do
      timeline.sections << section

      expect(timeline.has_events?).to be(true)
    end

    it "returns standalone events followed by section events" do
      timeline.events << standalone_event
      timeline.sections << section

      expect(timeline.all_events).to eq([standalone_event, section_event])
    end

    it "reports whether sections exist" do
      expect(timeline.has_sections?).to be(false)

      timeline.sections << section

      expect(timeline.has_sections?).to be(true)
    end
  end

  describe "#all_times" do
    it "returns unique times in sorted order across all events" do
      timeline.events.push(
        event("2022", "Standalone later"),
        event("2020", "Standalone earlier"),
      )
      section = Sirena::Diagram::TimelineSection.new("Middle")
      section.events.push(
        event("2021", "Section event"),
        event("2020", "Duplicate time"),
      )
      timeline.sections << section

      expect(timeline.all_times).to eq(%w[2020 2021 2022])
    end
  end
end
