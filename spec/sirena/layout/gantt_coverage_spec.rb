# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Gantt do
  let(:helper) { GanttCoverageScene }
  let(:jan_first) { Date.new(2024, 1, 1) }

  describe "durations" do
    {
      "weeks as seven days" => ["2w", Date.new(2024, 1, 15)],
      "hours round up to whole days" => ["36h", Date.new(2024, 1, 3)],
      "months move the calendar month" => ["1M", Date.new(2024, 2, 1)],
      "a bare number counts days" => ["5", Date.new(2024, 1, 6)],
    }.each do |name, (duration, finish)|
      it "reads #{name}" do
        scene = helper.scene_with_duration(duration)

        expect(helper.tasks(scene).first.end_date).to eq(finish)
      end
    end
  end

  describe "dependencies" do
    let(:one_to_three) { [Date.new(2024, 1, 1), Date.new(2024, 1, 3)] }
    let(:first_task) { "section A\nT1 :a, 2024-01-01, 2d\n" }

    it "ends an after task where an until task starts" do
      body = "#{first_task}T2 :after a, until c\nT3 :c, 2024-01-10, 2d\n"

      expect(helper.spans(helper.scene(body))[1])
        .to eq([Date.new(2024, 1, 3), Date.new(2024, 1, 10)])
    end

    it "leaves the end open when the until task is unknown" do
      body = "#{first_task}T2 :after a, until zz\n"

      expect(helper.spans(helper.scene(body))[1])
        .to eq([Date.new(2024, 1, 3), nil])
    end

    it "leaves the end open for an after task with nothing else" do
      body = "#{first_task}T2 :after a\n"

      expect(helper.spans(helper.scene(body))[1])
        .to eq([Date.new(2024, 1, 3), nil])
    end

    {
      "an unknown task" => ["T1 :after zz, 2d\n", [[nil, nil]]],
      "an until-only task" => ["T1 :until a\n", [[nil, nil]]],
      "a predecessor with no end" => ["T0 :2d\nT1 :2d\n",
                                      [[nil, nil], [nil, nil]]],
    }.each do |name, (lines, expected)|
      it "leaves a task unscheduled after #{name}" do
        scene = helper.scene("section A\n#{lines}")

        expect(helper.spans(scene)).to eq(expected)
      end
    end
  end

  describe "the timeline" do
    let(:flat) do
      helper.scene("section A\nT1 :a, 2024-01-10, 2024-01-08\n")
    end

    it "draws no date labels when the span is zero days" do
      expect(flat.timeline.labels).to be_empty
    end

    it "draws no grid lines when the span is zero days" do
      expect(flat.timeline.grid_lines).to be_empty
    end

    {
      "up to 120 days" => ["100d", 8],
      "up to 1200 days" => ["200d", 7],
    }.each do |name, (duration, count)|
      it "spaces labels for a span of #{name}" do
        scene = helper.scene("section A\nT1 :a, 2024-01-01, #{duration}\n")

        expect(scene.timeline.labels.size).to eq(count)
      end
    end
  end

  describe "a theme without typography" do
    let(:scene) do
      helper.scene("title Plan\nsection A\nT1 :a, 2024-01-01, 2d\n",
                   theme: Sirena::Theme.new)
    end
    let(:fallback) { Sirena::Theme::Registry.get(:default).typography }

    it "falls back to the default theme font sizes" do
      sizes = [scene.title, scene.sections.first.label,
               scene.sections.first.tasks.first.label].map(&:font_size)

      expect(sizes).to eq([fallback.font_size_large,
                           fallback.font_size_normal,
                           fallback.font_size_small])
    end
  end

  describe "a document without schedule settings" do
    let(:scene) do
      helper.lay_out(helper.settingless_document(
                       "section A\nT1 :a, 2024-01-01, 2d\n",
                     ))
    end

    it "still schedules the tasks" do
      expect(helper.spans(scene)).to eq([[jan_first, Date.new(2024, 1, 3)]])
    end

    it "labels dates in month-day form" do
      expect(scene.timeline.labels.first.text).to eq("12-31")
    end
  end
end
