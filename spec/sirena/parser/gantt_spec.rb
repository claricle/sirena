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
  end
end