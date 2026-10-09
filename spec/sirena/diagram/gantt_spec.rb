# frozen_string_literal: true

require "spec_helper"
require "sirena/diagram/gantt"

RSpec.describe Sirena::Diagram::Gantt do
  subject(:gantt) { described_class.new }

  describe Sirena::Diagram::GanttTask do
    subject(:task) { described_class.new }

    it "starts without tags or derived dates" do
      expect([task.tags, task.calculated_start, task.calculated_end])
        .to eq([[], nil, nil])
    end

    it "reports each supported status tag" do
      expect([task.done?, task.active?, task.critical?, task.milestone?])
        .to eq([false, false, false, false])

      task.tags = %w[done active crit milestone]

      expect([task.done?, task.active?, task.critical?, task.milestone?])
        .to eq([true, true, true, true])
    end
  end

  describe Sirena::Diagram::GanttSection do
    it "retains its name and starts without tasks" do
      section = described_class.new("Delivery")

      expect([section.name, section.tasks]).to eq(["Delivery", []])
    end
  end

  it "starts with Mermaid's default date format and empty collections" do
    expect([gantt.date_format, gantt.sections, gantt.excludes])
      .to eq(["YYYY-MM-DD", [], []])
  end

  it "defaults inclusive end dates to false" do
    expect(gantt.inclusive_end_dates).to be(false)
  end

  it "reports its diagram type and remains valid while validation is deferred" do
    expect([gantt.diagram_type, gantt.valid?]).to eq([:gantt, true])
  end
end
