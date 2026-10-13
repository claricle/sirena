# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/gantt"

RSpec.describe Sirena::Parser::Gantt do
  let(:parser) { described_class.new }

  describe "#parse" do
    context "when parsing a simple Gantt chart" do
      let(:source) do
        <<~GANTT
          gantt
            title Project Timeline
            dateFormat YYYY-MM-DD
            section Planning
            Task 1 :a1, 2024-01-01, 30d
        GANTT
      end
      let(:diagram) { parser.parse(source) }

      it "retains diagram" do
        expect(diagram).to be_a(Sirena::Diagram::Gantt)
      end

      it "retains diagram.title" do
        expect(diagram.title).to eq("Project Timeline")
      end

      it "retains diagram.date_format" do
        expect(diagram.date_format).to eq("YYYY-MM-DD")
      end

      it "retains diagram.sections.length" do
        expect(diagram.sections.length).to eq(1)
      end

      it "retains diagram.sections.first.name" do
        expect(diagram.sections.first.name).to eq("Planning")
      end

      it "retains diagram.sections.first.tasks.length" do
        expect(diagram.sections.first.tasks.length).to eq(1)
      end

      it "retains diagram.sections.first.tasks.first.description" do
        expect(diagram.sections.first.tasks.first.description).to eq("Task 1")
      end
    end

    context "when parsing Gantt with multiple sections" do
      let(:source) do
        <<~GANTT
          gantt
            section Planning
            Task 1 :a1, 2024-01-01, 30d
            section Development
            Task 2 :after a1, 20d
        GANTT
      end
      let(:diagram) { parser.parse(source) }

      it "retains diagram.sections.length" do
        expect(diagram.sections.length).to eq(2)
      end

      it "retains diagram.sections 0 .name" do
        expect(diagram.sections[0].name).to eq("Planning")
      end

      it "retains diagram.sections 1 .name" do
        expect(diagram.sections[1].name).to eq("Development")
      end
    end

    context "when parsing tasks with dependencies" do
      let(:source) do
        <<~GANTT
          gantt
            dateFormat YYYY-MM-DD
            section Tasks
            Task A :a, 2024-01-01, 10d
            Task B :b, after a, 5d
        GANTT
      end
      let(:diagram) { parser.parse(source) }

      it "retains tasks 0 .id" do
        tasks = diagram.sections.first.tasks

        expect(tasks[0].id).to eq("a")
      end

      it "retains tasks 1 .after_task" do
        tasks = diagram.sections.first.tasks

        expect(tasks[1].after_task).to eq("a")
      end
    end

    context "when parsing tasks with status tags" do
      let(:source) do
        <<~GANTT
          gantt
            section Tasks
            Done task :done, 2024-01-01, 5d
            Active task :active, 2024-01-06, 3d
            Critical task :crit, 2024-01-09, 2d
        GANTT
      end
      let(:diagram) { parser.parse(source) }

      it "retains tasks 0 .done" do
        tasks = diagram.sections.first.tasks

        expect(tasks[0].done?).to be true
      end

      it "retains tasks 1 .active" do
        tasks = diagram.sections.first.tasks

        expect(tasks[1].active?).to be true
      end

      it "retains tasks 2 .critical" do
        tasks = diagram.sections.first.tasks

        expect(tasks[2].critical?).to be true
      end
    end

    context "when parsing axis format configuration" do
      let(:source) do
        <<~GANTT
          gantt
            dateFormat YYYY-MM-DD
            axisFormat %m-%d
            section Tasks
            Task 1 :2024-01-01, 10d
        GANTT
      end
      let(:diagram) { parser.parse(source) }

      it "retains diagram.axis_format" do
        expect(diagram.axis_format).to eq("%m-%d")
      end
    end

    context "when parsing excludes configuration" do
      let(:source) do
        <<~GANTT
          gantt
            excludes weekends
            section Tasks
            Task 1 :2024-01-01, 10d
        GANTT
      end
      let(:diagram) { parser.parse(source) }

      it "retains diagram.excludes" do
        expect(diagram.excludes).to include("weekends")
      end
    end

    context "when parsing the weekend directive" do
      let(:source) do
        <<~GANTT
          gantt
            excludes weekends
            weekend friday
            section Tasks
            Task 1 :2024-01-01, 10d
        GANTT
      end
      let(:diagram) { parser.parse(source) }

      it "retains diagram.weekend" do
        expect(diagram.weekend).to eq("friday")
      end
    end

    context "when parsing the inclusiveEndDates directive" do
      let(:source) do
        <<~GANTT
          gantt
          dateFormat yyyy-mm-dd
          inclusiveEndDates
        GANTT
      end
      let(:diagram) { parser.parse(source) }

      it "retains diagram.inclusive_end_dates" do
        expect(diagram.inclusive_end_dates).to be(true)
      end
    end

    context "when defaults inclusiveEndDates to false when absent" do
      let(:source) do
        <<~GANTT
          gantt
          dateFormat yyyy-mm-dd
        GANTT
      end
      let(:diagram) { parser.parse(source) }

      it "retains diagram.inclusive_end_dates" do
        expect(diagram.inclusive_end_dates).to be(false)
      end
    end

    # Task detail fields (tags, id, dates, duration, after/until) are a
    # comma-separated list. Tags are stripped by keyword; what is left is
    # classified by POSITION — the id is always first when exactly three
    # value fields remain, regardless of what its text looks like
    # (corpus gantt/click_security_loose-0d2cc455).
    context "when parsing a tag, an id, and explicit start and end dates " \
            "in one task" do
      let(:source) do
        <<~GANTT
          gantt
            section Tasks
            Completed task            :done,    des1, 2014-01-06,2014-01-08
        GANTT
      end

      it "retains task.tags" do
        task = parser.parse(source).sections.first.tasks.first

        expect(task.tags).to eq(["done"])
      end

      it "retains task.id" do
        task = parser.parse(source).sections.first.tasks.first

        expect(task.id).to eq("des1")
      end

      it "retains task.start_date" do
        task = parser.parse(source).sections.first.tasks.first

        expect(task.start_date).to eq("2014-01-06")
      end

      it "retains task.end_date" do
        task = parser.parse(source).sections.first.tasks.first

        expect(task.end_date).to eq("2014-01-08")
      end
    end

    context "when parsing multiple comma-separated tags followed by a " \
            "duration" do
      let(:source) do
        <<~GANTT
          gantt
            section Tasks
            Create tests for parser             :crit, active, 3d
        GANTT
      end

      it "retains task.tags" do
        task = parser.parse(source).sections.first.tasks.first

        expect(task.tags).to eq(%w[crit active])
      end

      it "retains task.duration" do
        task = parser.parse(source).sections.first.tasks.first

        expect(task.duration).to eq("3d")
      end

      it "retains task.id" do
        task = parser.parse(source).sections.first.tasks.first

        expect(task.id).to be_nil
      end
    end

    it "parses comma-separated tags followed by an after-dependency and a " \
       "duration" do
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

    context "when parsing an after-dependency with trailing whitespace " \
            "before its comma" do
      let(:source) do
        <<~GANTT
          gantt
            section Tasks
            Add gantt diagram to demo page      :after a1  , 20h
        GANTT
      end

      it "retains task.after_task" do
        task = parser.parse(source).sections.first.tasks.first

        expect(task.after_task).to eq("a1")
      end

      it "retains task.duration" do
        task = parser.parse(source).sections.first.tasks.first

        expect(task.duration).to eq("20h")
      end
    end

    # An after-dependency supplies the START; a single date field left over
    # is therefore the task's END, never its start (Gantt reads
    # calculated_start only from the referenced task once after_task is
    # set, and end_date only from this field — see
    # Gantt#resolve_task_dependency).
    context "when treats a lone date after an after-dependency as the end " \
            "date" do
      let(:source) do
        <<~GANTT
          gantt
            dateFormat YYYY-MM-DD
            section Tasks
            Task A :a, 2024-01-01, 2024-01-03
            Task B :b, after a, 2024-01-10
        GANTT
      end

      it "retains task_b.start_date" do
        task_b = parser.parse(source).sections.first.tasks[1]

        expect(task_b.start_date).to be_nil
      end

      it "retains task_b.end_date" do
        task_b = parser.parse(source).sections.first.tasks[1]

        expect(task_b.end_date).to eq("2024-01-10")
      end
    end

    # Three value fields (tags stripped, but an after/until dependency still
    # counted — see the "counts an after-dependency..." example below) is
    # mermaid's "id, start, end/duration" shape. The id is always the first
    # of the three, even when its text happens to look like a date.
    it "treats the first of three value fields as the id, even when it is " \
       "date-shaped" do
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
    context "when counts an after-dependency field toward the three-value " \
            "id rule" do
      let(:source) do
        <<~GANTT
          gantt
            dateFormat YYYY-MM-DD
            section Tasks
            T: 2024-01-01, after a, 2024-01-06
        GANTT
      end

      it "retains task.id" do
        task = parser.parse(source).sections.first.tasks.first

        expect(task.id).to eq("2024-01-01")
      end

      it "retains task.after_task" do
        task = parser.parse(source).sections.first.tasks.first

        expect(task.after_task).to eq("a")
      end

      it "retains task.start_date" do
        task = parser.parse(source).sections.first.tasks.first

        expect(task.start_date).to be_nil
      end

      it "retains task.end_date" do
        task = parser.parse(source).sections.first.tasks.first

        expect(task.end_date).to eq("2024-01-06")
      end
    end

    # `dateFormat YYYYMMDD` produces separator-less date fields like
    # "20240101". Once the id already came from the three-slot positional
    # rule, a leftover field like that must still be treated as a date and
    # never re-trigger id-by-shape classification, or it silently
    # overwrites the real id.
    it "keeps the positional id when trailing dates have no separator " \
       "(compact dateFormat)" do
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

    # Outside the three-slot case there is no id field at all: with no
    # explicit id given, two leftover fields are always start/end BY
    # POSITION, never an id-by-shape guess — even when the first one fails
    # to look like a date, which a compact `dateFormat YYYYMMDD` value
    # always does. Measured against mmdc: `T: 20240101, 20240103` renders
    # both fields as the task's dates, with mermaid auto-generating the id
    # (Codex High, gantt.rb:207 — this exact input used to produce
    # `id="20240103"` with both dates nil).
    it "treats two leftover compact-date fields as start/end when no id is " \
       "given" do
      source = <<~GANTT
        gantt
          dateFormat YYYYMMDD
          section Tasks
          T: 20240101, 20240103
      GANTT

      task = parser.parse(source).sections.first.tasks.first

      expect(task.id).to be_nil
      expect(task.start_date).to eq("20240101")
      expect(task.end_date).to eq("20240103")
    end
  end

  describe "#parse settings lines" do
    {
      "tick_interval" => ["tickInterval 1week", "1week"],
      "today_marker" => ["todayMarker off", "off"],
    }.each do |attribute, (line, expected)|
      it "reads #{attribute} from #{line.inspect}" do
        source = "gantt\n  #{line}\n  section A\n  T :a, 2024-01-01, 2d\n"

        expect(parser.parse(source).public_send(attribute)).to eq(expected)
      end
    end
  end
end
