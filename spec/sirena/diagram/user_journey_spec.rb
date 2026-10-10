# frozen_string_literal: true

require "spec_helper"
require "sirena/diagram/user_journey"

RSpec.describe Sirena::Diagram::UserJourney do
  def journey_task(name, score, actors = [])
    Sirena::Diagram::JourneyTask.new(name: name, score: score, actors: actors)
  end

  def journey_section(name:, tasks:)
    Sirena::Diagram::JourneySection.new.tap do |section|
      section.name = name
      section.tasks.concat(tasks)
    end
  end

  def user_journey(*sections)
    described_class.new.tap { |diagram| diagram.sections.concat(sections) }
  end

  def user_journey_with(*task_groups)
    sections = task_groups.each_with_index.map do |tasks, index|
      journey_section(name: "Section #{index + 1}", tasks: tasks)
    end
    user_journey(*sections)
  end

  describe Sirena::Diagram::JourneyTask do
    describe "#valid?" do
      it "returns true for task with all required fields" do
        task = journey_task("Browse products", 5, ["Customer"])

        expect(task.valid?).to be true
      end

      it "returns false for task without name" do
        task = described_class.new.tap do |t|
          t.score = 5
          t.actors = ["Customer"]
        end

        expect(task.valid?).to be false
      end

      it "returns false for task without score" do
        task = described_class.new.tap do |t|
          t.name = "Browse products"
          t.actors = ["Customer"]
        end

        expect(task.valid?).to be false
      end

      it "returns false for task with invalid score" do
        task = journey_task("Browse products", 6, ["Customer"])

        expect(task.valid?).to be false
      end

      it "returns false for a score below the supported range" do
        task = described_class.new(
          name: "Browse products", score: 0, actors: ["Customer"],
        )

        expect(task.valid?).to be false
      end

      it "returns true for task with an empty actor list" do
        # mmdc renders `Task: 5` and `Task: 5:` (corpus cases 004/008/012)
        # the same as a task with actors; `actors` defaults to `[]`.
        task = described_class.new(name: "Browse products", score: 5)

        expect(task).to have_attributes(actors: [], valid?: true)
      end
    end

    describe "#score_color" do
      it "returns red for low scores (1-2)" do
        task = described_class.new.tap do |t|
          t.score = 1
        end

        expect(task.score_color).to eq(:red)
      end

      it "returns yellow for medium score (3)" do
        task = described_class.new.tap do |t|
          t.score = 3
        end

        expect(task.score_color).to eq(:yellow)
      end

      it "returns green for high scores (4-5)" do
        task = described_class.new.tap do |t|
          t.score = 5
        end

        expect(task.score_color).to eq(:green)
      end

      it "returns yellow for a score outside the supported range" do
        task = described_class.new(score: 0)

        expect(task.score_color).to eq(:yellow)
      end
    end
  end

  describe Sirena::Diagram::JourneySection do
    describe "#valid?" do
      it "returns true for section with name and valid tasks" do
        task = journey_task("Browse", 5, ["Customer"])
        section = journey_section(name: "Shopping", tasks: [task])

        expect(section.valid?).to be true
      end

      it "returns false for section without name" do
        section = described_class.new

        expect(section.valid?).to be false
      end
    end
  end

  describe Sirena::Diagram::UserJourney do
    describe "#diagram_type" do
      it "returns :user_journey" do
        diagram = described_class.new

        expect(diagram.diagram_type).to eq(:user_journey)
      end
    end

    describe "#valid?" do
      it "returns true for valid user journey with sections" do
        task = journey_task("Browse", 5, ["Customer"])
        section = journey_section(name: "Shopping", tasks: [task])
        diagram = user_journey(section)

        expect(diagram.valid?).to be true
      end

      it "returns true for journey without sections" do
        # mmdc renders a bare `journey` (with or without a title) as an
        # empty diagram; corpus cases 014/015/024/025 are exactly this.
        diagram = described_class.new

        expect(diagram.valid?).to be true
      end

      it "returns true for journey with a title and no sections" do
        # Corpus cases 003/007: `journey` + `title ...` with no sections.
        diagram = described_class.new
        diagram.title = "Adding journey diagram functionality to mermaid"

        expect(diagram.valid?).to be true
      end

      it "returns false when sections is explicitly nil" do
        # An empty array is a valid bare journey; nil is not the same thing.
        # Layout dereferences sections directly and raises NoMethodError on
        # nil, so nil must stay rejected here rather than treated as empty.
        #
        # Diagnostic, not a fix-proving spec: origin/main's old `valid?` also
        # rejects nil sections (its own `sections.nil?` guard), so this example
        # passes unchanged against the pre-fix code too. Keep it anyway -- it
        # becomes the only check catching a regression if `valid?` is ever
        # rewritten to treat nil the same as empty.
        diagram = described_class.new
        diagram.sections = nil

        expect(diagram.valid?).to be false
      end
    end

    describe "#all_tasks" do
      it "returns all tasks across all sections" do
        task1 = journey_task("Task 1", 5, ["Actor 1"])
        task2 = journey_task("Task 2", 3, ["Actor 2"])
        diagram = user_journey_with([task1], [task2])

        expect(diagram.all_tasks.length).to eq(2)
      end
    end

    describe "#all_actors" do
      it "returns unique actors from all tasks" do
        task1 = journey_task("Task 1", 5, ["Actor 1", "Actor 2"])
        task2 = journey_task("Task 2", 3, ["Actor 2", "Actor 3"])
        diagram = user_journey_with([task1, task2])
        expected = ["Actor 1", "Actor 2", "Actor 3"]

        expect(diagram.all_actors).to match_array(expected)
      end
    end

    describe "#tasks_by_score" do
      it "filters tasks by score" do
        task1 = journey_task("Task 1", 5, ["Actor 1"])
        task2 = journey_task("Task 2", 3, ["Actor 2"])
        diagram = user_journey_with([task1, task2])
        expected = have_attributes(name: "Task 1")

        expect(diagram.tasks_by_score(5)).to contain_exactly(expected)
      end
    end
  end
end
