# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/timeline"

RSpec.describe Sirena::Parser::Timeline, :aggregate_failures do
  let(:parser) { described_class.new }

  context "when parsing a simple timeline" do
    let(:source) do
      <<~TIMELINE
        timeline
          title History of Social Media
          2002 : LinkedIn
          2004 : Facebook
          2005 : YouTube
      TIMELINE
    end
    let(:diagram) { parser.parse(source) }

    it "retains diagram" do
      expect(diagram).to be_a(Sirena::Diagram::Timeline)
    end

    it "retains diagram.title" do
      expect(diagram.title).to eq("History of Social Media")
    end

    it "retains diagram.events.length" do
      expect(diagram.events.length).to eq(3)
    end

    it "retains diagram.events 0 .time" do
      expect(diagram.events[0].time).to eq("2002")
    end

    it "retains diagram.events 0 .descriptions" do
      expect(diagram.events[0].descriptions).to include("LinkedIn")
    end
  end

  context "when parsing timeline with multiple descriptions per event" do
    let(:source) do
      <<~TIMELINE
        timeline
          2004 : Facebook : Google
      TIMELINE
    end
    let(:diagram) { parser.parse(source) }

    it "retains diagram.events.length" do
      expect(diagram.events.length).to eq(1)
    end

    it "retains diagram.events 0 .time" do
      expect(diagram.events[0].time).to eq("2004")
    end

    it "retains diagram.events 0 .descriptions" do
      expect(diagram.events[0].descriptions).to eq(["Facebook", "Google"])
    end

    it "retains diagram.events 0 .multiple_descriptions" do
      expect(diagram.events[0].multiple_descriptions?).to be true
    end
  end

  context "when parsing timeline with sections" do
    let(:source) do
      <<~TIMELINE
        timeline
          section 20th Century
          1969 : Moon landing
          section 21st Century
          2007 : iPhone released
      TIMELINE
    end
    let(:diagram) { parser.parse(source) }

    it "retains diagram.sections.length" do
      expect(diagram.sections.length).to eq(2)
    end

    it "retains diagram.sections 0 .name" do
      expect(diagram.sections[0].name).to eq("20th Century")
    end

    it "retains diagram.sections 1 .name" do
      expect(diagram.sections[1].name).to eq("21st Century")
    end

    it "retains diagram.sections 0 .events.length" do
      expect(diagram.sections[0].events.length).to eq(1)
    end

    it "retains diagram.sections 1 .events.length" do
      expect(diagram.sections[1].events.length).to eq(1)
    end
  end

  context "when parsing timeline with tasks in sections" do
    let(:source) do
      <<~TIMELINE
        timeline
          section Tasks
          task1
          task2
      TIMELINE
    end
    let(:diagram) { parser.parse(source) }

    it "retains diagram.sections.length" do
      expect(diagram.sections.length).to eq(1)
    end

    it "retains diagram.sections 0 .tasks" do
      expect(diagram.sections[0].tasks).to eq(["task1", "task2"])
    end
  end

  context "when parsing timeline with continuation entries" do
    let(:source) do
      <<~TIMELINE
        timeline
          2004 : Facebook
               : Google
      TIMELINE
    end
    let(:diagram) { parser.parse(source) }

    it "retains diagram.events.length" do
      expect(diagram.events.length).to eq(1)
    end

    it "retains diagram.events 0 .descriptions" do
      expect(diagram.events[0].descriptions).to eq(["Facebook", "Google"])
    end
  end

  context "when parsing timeline with accessibility features" do
    let(:source) do
      <<~TIMELINE
        timeline
          accTitle: My Timeline
          accDescr: A historical timeline
          2020 : Event
      TIMELINE
    end
    let(:diagram) { parser.parse(source) }

    it "retains diagram.acc_title" do
      expect(diagram.acc_title).to eq("My Timeline")
    end

    it "retains diagram.acc_description" do
      expect(diagram.acc_description).to eq("A historical timeline")
    end
  end

  context "when handles special characters in content" do
    let(:source) do
      <<~TIMELINE
        timeline
          title ;my;title;
          section ;abc-123;
          ;task1;
      TIMELINE
    end
    let(:diagram) { parser.parse(source) }

    it "retains diagram.title" do
      expect(diagram.title).to eq(";my;title;")
    end

    it "retains diagram.sections 0 .name" do
      expect(diagram.sections[0].name).to eq(";abc-123;")
    end

    it "retains diagram.sections 0 .tasks" do
      expect(diagram.sections[0].tasks).to include(";task1;")
    end
  end

  it "keeps a trailing semicolon on an event description" do
    diagram = parser.parse("timeline\n  2020 : ;ev;ent;\n")

    expect(diagram.events[0].descriptions).to eq([";ev;ent;"])
  end

  it "keeps a colon that is not followed by whitespace" do
    diagram = parser.parse("timeline\n  2020 : see http://a.b : two\n")

    expect(diagram.events[0].descriptions).to eq(["see http://a.b", "two"])
  end

  context "when validates parsed timeline" do
    let(:source) do
      <<~TIMELINE
        timeline
          2020 : COVID-19
      TIMELINE
    end
    let(:diagram) { parser.parse(source) }

    it "retains diagram.valid" do
      expect(diagram.valid?).to be true
    end

    it "retains diagram.has_events" do
      expect(diagram.has_events?).to be true
    end
  end

  it "keeps no task for a line of only a vertical tab" do
    diagram = parser.parse("timeline\n\v\nsection S\n\v\n")

    expect(diagram.sections.map(&:tasks)).to eq([[]])
  end

  it "raises error on invalid syntax" do
    source = "invalid timeline syntax"

    expect { parser.parse(source) }.to raise_error(Sirena::Parser::ParseError)
  end
end
