# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/gantt"

RSpec.describe Sirena::Parser::GanttParser do
  let(:parser) { described_class.new }

  describe "#parse" do
    it "parses a simple Gantt chart" do
      source = <<~GANTT
        gantt
          title Project Timeline
          dateFormat YYYY-MM-DD
          section Planning
          Task 1 :a1, 2024-01-01, 30d
      GANTT

      diagram = parser.parse(source)

      expect(diagram).to be_a(Sirena::Diagram::GanttChart)
      expect(diagram.title).to eq("Project Timeline")
      expect(diagram.date_format).to eq("YYYY-MM-DD")
      expect(diagram.sections.length).to eq(1)
      expect(diagram.sections.first.name).to eq("Planning")
      expect(diagram.sections.first.tasks.length).to eq(1)
      expect(diagram.sections.first.tasks.first.description).to eq("Task 1")
    end

    it "parses Gantt with multiple sections" do
      source = <<~GANTT
        gantt
          section Planning
          Task 1 :a1, 2024-01-01, 30d
          section Development
          Task 2 :after a1, 20d
      GANTT

      diagram = parser.parse(source)

      expect(diagram.sections.length).to eq(2)
      expect(diagram.sections[0].name).to eq("Planning")
      expect(diagram.sections[1].name).to eq("Development")
    end

    it "parses tasks with dependencies" do
      source = <<~GANTT
        gantt
          dateFormat YYYY-MM-DD
          section Tasks
          Task A :a, 2024-01-01, 10d
          Task B :b, after a, 5d
      GANTT

      diagram = parser.parse(source)
      tasks = diagram.sections.first.tasks

      expect(tasks[0].id).to eq("a")
      expect(tasks[1].after_task).to eq("a")
    end

    it "parses tasks with status tags" do
      source = <<~GANTT
        gantt
          section Tasks
          Done task :done, 2024-01-01, 5d
          Active task :active, 2024-01-06, 3d
          Critical task :crit, 2024-01-09, 2d
      GANTT

      diagram = parser.parse(source)
      tasks = diagram.sections.first.tasks

      expect(tasks[0].done?).to be true
      expect(tasks[1].active?).to be true
      expect(tasks[2].critical?).to be true
    end

    it "parses axis format configuration" do
      source = <<~GANTT
        gantt
          dateFormat YYYY-MM-DD
          axisFormat %m-%d
          section Tasks
          Task 1 :2024-01-01, 10d
      GANTT

      diagram = parser.parse(source)

      expect(diagram.axis_format).to eq("%m-%d")
    end

    it "parses excludes configuration" do
      source = <<~GANTT
        gantt
          excludes weekends
          section Tasks
          Task 1 :2024-01-01, 10d
      GANTT

      diagram = parser.parse(source)

      expect(diagram.excludes).to include("weekends")
    end

    # Task detail fields (tags, id, dates, duration, after/until) are a
    # comma-separated list with no fixed position — mermaid classifies each
    # field by its own shape rather than by where it sits (corpus gantt/005).
    it "parses a tag, an id, and explicit start and end dates in one task" do
      source = <<~GANTT
        gantt
          section Tasks
          Completed task            :done,    des1, 2014-01-06,2014-01-08
      GANTT

      task = parser.parse(source).sections.first.tasks.first

      expect(task.tags).to eq(["done"])
      expect(task.id).to eq("des1")
      expect(task.start_date).to eq("2014-01-06")
      expect(task.end_date).to eq("2014-01-08")
    end

    it "parses multiple comma-separated tags followed by a duration" do
      source = <<~GANTT
        gantt
          section Tasks
          Create tests for parser             :crit, active, 3d
      GANTT

      task = parser.parse(source).sections.first.tasks.first

      expect(task.tags).to eq(%w[crit active])
      expect(task.duration).to eq("3d")
      expect(task.id).to be_nil
    end

    it "parses comma-separated tags followed by an after-dependency and a duration" do
      source = <<~GANTT
        gantt
          section Tasks
          Implement parser and jison          :crit, done, after des1, 2d
      GANTT

      task = parser.parse(source).sections.first.tasks.first

      expect(task.tags).to eq(%w[crit done])
      expect(task.after_task).to eq("des1")
      expect(task.duration).to eq("2d")
    end

    it "parses an after-dependency with trailing whitespace before its comma" do
      source = <<~GANTT
        gantt
          section Tasks
          Add gantt diagram to demo page      :after a1  , 20h
      GANTT

      task = parser.parse(source).sections.first.tasks.first

      expect(task.after_task).to eq("a1")
      expect(task.duration).to eq("20h")
    end

    # An after-dependency supplies the START; a single date field left over
    # is therefore the task's END, never its start (GanttTransform reads
    # calculated_start only from the referenced task once after_task is
    # set, and end_date only from this field — see
    # GanttTransform#resolve_task_dependency).
    it "treats a lone date after an after-dependency as the end date" do
      source = <<~GANTT
        gantt
          dateFormat YYYY-MM-DD
          section Tasks
          Task A :a, 2024-01-01, 2024-01-03
          Task B :b, after a, 2024-01-10
      GANTT

      task_b = parser.parse(source).sections.first.tasks[1]

      expect(task_b.start_date).to be_nil
      expect(task_b.end_date).to eq("2024-01-10")
    end

    # Three value fields (tags stripped, but an after/until dependency still
    # counted — see the "counts an after-dependency..." example below) is
    # mermaid's "id, start, end/duration" shape. The id is always the first
    # of the three, even when its text happens to look like a date.
    it "treats the first of three value fields as the id, even when it is date-shaped" do
      source = <<~GANTT
        gantt
          dateFormat YYYY-MM-DD
          section Tasks
          A : 2024-01-01, 2024-02-01, 2024-02-03
      GANTT

      task = parser.parse(source).sections.first.tasks.first

      expect(task.id).to eq("2024-01-01")
      expect(task.start_date).to eq("2024-02-01")
      expect(task.end_date).to eq("2024-02-03")
    end

    # An "after"/"until" dependency fills the same positional slot a bare
    # date would (id, start, end), so it must count toward the three-value
    # id rule above even though it is stripped out separately afterward.
    # Counting only the fields left once the dependency is already gone
    # under-counts to two, skips the id assignment, and silently drops a
    # date-shaped id that a later "after <that id>" reference depends on.
    it "counts an after-dependency field toward the three-value id rule" do
      source = <<~GANTT
        gantt
          dateFormat YYYY-MM-DD
          section Tasks
          T: 2024-01-01, after a, 2024-01-06
      GANTT

      task = parser.parse(source).sections.first.tasks.first

      expect(task.id).to eq("2024-01-01")
      expect(task.after_task).to eq("a")
      expect(task.start_date).to be_nil
      expect(task.end_date).to eq("2024-01-06")
    end

    # `dateFormat YYYYMMDD` produces separator-less date fields like
    # "20240101", which DATE_PATTERN does not match (it requires a
    # "-", "/" or ":"). Once the id already came from position, a leftover
    # field like that must still be treated as a date and never re-trigger
    # id-by-shape classification, or it silently overwrites the real id.
    it "keeps the positional id when trailing dates have no separator (compact dateFormat)" do
      source = <<~GANTT
        gantt
          dateFormat YYYYMMDD
          section Tasks
          T: t, 20240101, 20240103
      GANTT

      task = parser.parse(source).sections.first.tasks.first

      expect(task.id).to eq("t")
      expect(task.start_date).to eq("20240101")
      expect(task.end_date).to eq("20240103")
    end
  end
end