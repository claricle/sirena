# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Gantt do
  let(:helper) { GanttCoverageScene }
  let(:unit_durations) { %w[500ms 30s 90m 20h 2d 2w 2M 2y] }
  let(:parsed_durations) do
    unit_durations.map do |duration|
      helper.parse(
        "section A\nTask :id, 2024-01-31, #{duration}\n",
      ).sections.first.tasks.first.duration
    end
  end
  let(:fractional_results) do
    %w[1.5d 1.5w 1.5M 1.5y].to_h do |duration|
      [duration, task_for(duration)]
    end
  end
  let(:expected_fractional_results) do
    {
      "1.5d" => ["1.5d", Date.new(2024, 2, 2)],
      "1.5w" => ["1.5w", Date.new(2024, 2, 11)],
      "1.5M" => ["1.5M", Date.new(2024, 2, 29)],
      "1.5y" => ["1.5y", Date.new(2025, 1, 31)],
    }
  end

  def task_for(duration)
    body = "section A\nTask :id, 2024-01-31, #{duration}\n"
    document = helper.parse(body)
    scene = helper.lay_out(document)
    [document.sections.first.tasks.first.duration,
     helper.tasks(scene).first.end_date]
  end

  it "accepts every pinned Mermaid duration unit through the public parser" do
    expect(parsed_durations).to eq(unit_durations)
  end

  it "matches pinned Day.js rounding for fractional calendar durations" do
    expect(fractional_results).to eq(expected_fractional_results)
  end
end
