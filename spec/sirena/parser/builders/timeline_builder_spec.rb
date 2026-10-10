# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Builders::Timeline do
  subject(:diagram) { described_class.new.apply(tree) }

  context "with an array tree" do
    let(:tree) do
      [{ header: "timeline" },
       { event_entry: { time: "2021", descriptions: { desc: "single" } } }]
    end

    it "adds section-less events to the diagram" do
      expect(diagram.events.map do |e|
        [e.time, e.descriptions]
      end).to eq([["2021", ["single"]]])
    end
  end

  context "with nil event and continuation entries" do
    let(:tree) { [{ event_entry: nil }, { continuation_entry: nil }] }

    it "ignores them" do
      expect(diagram.events).to be_empty
    end
  end

  context "with a continuation before any event" do
    let(:tree) do
      [{ continuation_entry: { descriptions: [{ desc: "orphan" }] } },
       { continuation_entry: { descriptions: [{ desc: "more" }] } }]
    end

    it "creates an event with an empty time and extends it afterwards" do
      expect(diagram.events.map do |e|
        [e.time, e.descriptions]
      end).to eq([["", %w[orphan more]]])
    end
  end

  context "with a continuation before any event but inside a section" do
    let(:tree) do
      [{ section: "S" },
       { continuation_entry: { descriptions: [{ desc: "orphan" }] } }]
    end

    it "puts the synthesised event in the section" do
      events = diagram.sections.first.events
      expect(events.map(&:descriptions)).to eq([["orphan"]])
    end
  end

  context "with event descriptions absent" do
    let(:tree) { [{ event_entry: { time: "T" } }] }

    it "creates an event without descriptions" do
      expect(diagram.events.first.descriptions).to be_empty
    end
  end

  context "with a task before any section" do
    let(:tree) { [{ task: "first" }] }

    it "opens a Default section" do
      expect(diagram.sections.map do |s|
        [s.name, s.tasks]
      end).to eq([["Default", ["first"]]])
    end
  end

  context "with a section after events" do
    let(:tree) do
      [{ event_entry: { time: "1", descriptions: [] } }, { section: "S" },
       { continuation_entry: { descriptions: [{ desc: "x" }] } }]
    end

    it "does not attach a continuation to an event from before the section",
       :aggregate_failures do
      expect(diagram.events.first.descriptions).to be_empty
      expect(diagram.sections.first.events.first.descriptions).to eq(["x"])
    end
  end
end
