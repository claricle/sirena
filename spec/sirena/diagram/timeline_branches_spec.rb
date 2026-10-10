# frozen_string_literal: true

require "spec_helper"
require "sirena/diagram/timeline"

RSpec.describe Sirena::Diagram::Timeline do
  def task_only_timeline
    section = Sirena::Diagram::TimelineSection.new("Delivery")
    section.tasks << "Ship"
    timeline = described_class.new
    timeline.sections << section
    [timeline, section]
  end

  it "reports no events or times when empty" do
    timeline = described_class.new

    expect([timeline.has_events?, timeline.all_events, timeline.all_times])
      .to eq([false, [], []])
  end

  it "does not treat a task-only section as an event" do
    timeline, section = task_only_timeline

    expect([timeline.has_sections?, timeline.has_events?, section.has_tasks?])
      .to eq([true, false, true])
  end
end
