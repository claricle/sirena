# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/timeline"

RSpec.describe Sirena::Notation::Mermaid::IRAdapters::Timeline do
  let(:diagram) do
    Sirena::Diagram::Timeline.new.tap do |timeline|
      timeline.id = "section_0"
      timeline.title = "Launch history"
      timeline.acc_title = "Accessible history"
      timeline.acc_description = "Launches over time"
      timeline.sections << history_section
      timeline.events << timeline_event("2024", "Released")
    end
  end
  let(:ir) { described_class.call(diagram) }

  it "produces valid collision-free pre-positioned IR" do
    expect(ir).to be_valid
  end

  it "preserves root identity, title, and accessibility" do
    expect(root_signature)
      .to eq(["section_0", "Launch history", "chronology",
              "Accessible history", "Launches over time"])
  end

  it "preserves ordered containment and source-domain placements" do
    expect(item_signatures).to eq(expected_items)
  end

  def history_section
    Sirena::Diagram::TimelineSection.new("History").tap do |section|
      section.events << timeline_event("2020", "Started", "Expanded")
      section.tasks << "Research"
    end
  end

  def timeline_event(time, *descriptions)
    Sirena::Diagram::TimelineEvent.new.tap do |event|
      event.time = time
      event.descriptions = descriptions
    end
  end

  def root_signature
    [ir.id, ir.label, ir.role, ir.accessibility_title,
     ir.accessibility_description]
  end

  def item_signatures
    ir.items.map do |item|
      placement = item.placements.first
      [item.id, item.label, item.role, item.parent_id,
       placement.dimension, placement.ordinal, placement.value.value]
    end
  end

  def expected_items
    [["section_0_2", "History", "section", nil, "track", 0, 0.0],
     ["event_0", "2020", "event", "section_0_2", "time", 0, "2020"],
     ["description_0", "Started", "description", "event_0",
      "description", 0, 0.0],
     ["description_1", "Expanded", "description", "event_0",
      "description", 1, 1.0],
     ["task_0", "Research", "task", "section_0_2", "task", 0, 0.0],
     ["event_0_2", "2024", "event", nil, "time", 0, "2024"],
     ["description_0_2", "Released", "description", "event_0_2",
      "description", 0, 0.0]]
  end
end
