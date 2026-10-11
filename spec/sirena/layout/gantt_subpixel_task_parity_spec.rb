# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Gantt do
  subject(:task) do
    source = "gantt\n  dateFormat YYYY-MM-DD\n  section Work\n#{tasks}"
    diagram = Sirena::Parser::Gantt.new.parse(source)
    scene = described_class.new.call(diagram, today: reference_date)
    scene.sections.first.tasks.last
  end

  let(:reference_date) { Date.new(2024, 1, 1) }

  context "with an ordinary zero-duration task" do
    let(:tasks) { "Zero :zero, 2024-01-01, 0d" }

    it "keeps the task as a zero-width rectangle" do
      expect([task.bar.width, task.milestone_points]).to eq([0, nil])
    end
  end

  context "with an ordinary task narrower than one pixel" do
    let(:tasks) do
      <<~TASKS
        Span :span, 2024-01-01, 3650d
        Brief :brief, 2024-01-01, 1h
      TASKS
    end

    it "collapses the task instead of drawing a diamond" do
      expect([task.bar.width, task.milestone_points]).to eq([0, nil])
    end
  end

  context "with an explicitly tagged milestone" do
    let(:tasks) { "Release :milestone, release, 2024-01-01, 0d" }

    it "draws a diamond without a task bar" do
      expect([task.bar, task.milestone_points]).to eq(
        [nil, "600,132 612,120 624,132 612,144"],
      )
    end
  end
end
