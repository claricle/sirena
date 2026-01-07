# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/timeline"

RSpec.describe Sirena::Parser::TimelineParser do
  let(:parser) { described_class.new }

  describe "#parse" do
    it "parses a simple timeline" do
      source = <<~TIMELINE
        timeline
          title History of Social Media
          2002 : LinkedIn
          2004 : Facebook
          2005 : YouTube
      TIMELINE

      diagram = parser.parse(source)

      expect(diagram).to be_a(Sirena::Diagram::Timeline)
      expect(diagram.title).to eq("History of Social Media")
      expect(diagram.events.length).to eq(3)
      expect(diagram.events[0].time).to eq("2002")
      expect(diagram.events[0].descriptions).to include("LinkedIn")
    end

    it "parses timeline with multiple descriptions per event" do
      source = <<~TIMELINE
        timeline
          2004 : Facebook : Google
      TIMELINE

      diagram = parser.parse(source)

      expect(diagram.events.length).to eq(1)
      expect(diagram.events[0].time).to eq("2004")
      expect(diagram.events[0].descriptions).to eq(["Facebook", "Google"])
      expect(diagram.events[0].multiple_descriptions?).to be true
    end

    it "parses timeline with sections" do
      source = <<~TIMELINE
        timeline
          section 20th Century
          1969 : Moon landing
          section 21st Century
          2007 : iPhone released
      TIMELINE

      diagram = parser.parse(source)

      expect(diagram.sections.length).to eq(2)
      expect(diagram.sections[0].name).to eq("20th Century")
      expect(diagram.sections[1].name).to eq("21st Century")
      expect(diagram.sections[0].events.length).to eq(1)
      expect(diagram.sections[1].events.length).to eq(1)
    end

    it "parses timeline with tasks in sections" do
      source = <<~TIMELINE
        timeline
          section Tasks
          task1
          task2
      TIMELINE

      diagram = parser.parse(source)

      expect(diagram.sections.length).to eq(1)
      expect(diagram.sections[0].tasks).to eq(["task1", "task2"])
    end

    it "parses timeline with continuation entries" do
      source = <<~TIMELINE
        timeline
          2004 : Facebook
               : Google
      TIMELINE

      diagram = parser.parse(source)

      expect(diagram.events.length).to eq(1)
      expect(diagram.events[0].descriptions).to eq(["Facebook", "Google"])
    end

    it "parses timeline with accessibility features" do
      source = <<~TIMELINE
        timeline
          accTitle: My Timeline
          accDescr: A historical timeline
          2020 : Event
      TIMELINE

      diagram = parser.parse(source)

      expect(diagram.acc_title).to eq("My Timeline")
      expect(diagram.acc_description).to eq("A historical timeline")
    end

    it "handles special characters in content" do
      source = <<~TIMELINE
        timeline
          title ;my;title;
          section ;abc-123;
          ;task1;
      TIMELINE

      diagram = parser.parse(source)

      # Trailing semicolons are stripped as line terminators
      expect(diagram.title).to eq(";my;title")
      expect(diagram.sections[0].name).to eq(";abc-123")
      expect(diagram.sections[0].tasks).to include(";task1")
    end

    it "validates parsed timeline" do
      source = <<~TIMELINE
        timeline
          2020 : COVID-19
      TIMELINE

      diagram = parser.parse(source)

      expect(diagram.valid?).to be true
      expect(diagram.has_events?).to be true
    end

    it "raises error on invalid syntax" do
      source = "invalid timeline syntax"

      expect { parser.parse(source) }.to raise_error(Sirena::Parser::ParseError)
    end
  end
end