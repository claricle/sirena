# frozen_string_literal: true

require "spec_helper"

# Expected ends and ticks were read off mmdc's SVG for the same source
# (spec/fixtures_mermaid/gantt/002 and 005).
RSpec.describe Sirena::Layout::Gantt do
  let(:helper) { GanttCoverageScene }
  let(:friday_weekend) do
    "excludes weekends\nweekend friday\nsection S\nA :a1, 2024-02-28, 10d\n"
  end

  def iso_span(scene)
    helper.spans(scene).first.map(&:iso8601)
  end

  def tasks_of(first, second)
    "section S\nA :2024-01-01, #{first}\nB :2024-01-01, #{second}\n"
  end

  def widths(body)
    helper.tasks(helper.scene(body)).map { |task| task.bar.width }
  end

  it "ends a task after the weekend days its duration crosses" do
    scene = helper.scene(friday_weekend)

    expect(iso_span(scene)).to eq(%w[2024-02-28 2024-03-13])
  end

  it "ticks to the pushed end" do
    scene = helper.scene(friday_weekend)

    expect(scene.timeline.labels.last.text).to eq("2024-03-13")
  end

  it "leaves an end written as a date where it is" do
    body = "excludes weekends\nsection S\nA :a1, 2024-03-01, 2024-03-04\n"

    expect(iso_span(helper.scene(body))).to eq(%w[2024-03-01 2024-03-04])
  end

  it "draws the bar to the end before an excluded stretch" do
    body = "excludes weekends\nsection S\nA :2024-03-07, 2d\nB :2024-03-11, 2d\n"
    drawn, whole = widths(body)

    expect(drawn / whole).to be_within(0.001).of(1.0)
  end

  it "starts the next task after the excluded stretch" do
    body = "excludes weekends\nsection S\nA :a, 2024-03-07, 2d\nB :after a, 1d\n"

    expect(helper.spans(helper.scene(body)).last.first.iso8601)
      .to eq("2024-03-11")
  end

  it "draws a day of hours as long as a day" do
    hours, days = widths(tasks_of("24h", "1d"))

    expect(hours).to eq(days)
  end

  it "draws hours shorter than a whole day" do
    hours, days = widths(tasks_of("20h", "1d"))

    expect(hours / days).to be_within(0.001).of(20.0 / 24)
  end
end
