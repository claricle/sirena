# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/gantt"

RSpec.describe Sirena::Notation::Mermaid::IRAdapters::Gantt do
  subject(:ir) { described_class.call(diagram) }

  let(:diagram) do
    section = Sirena::Diagram::GanttSection.new("Work")
    section.tasks = [task(nil, nil), task("", "missing")]
    Sirena::Diagram::Gantt.new.tap do |gantt|
      gantt.id = ""
      gantt.sections = [section]
    end
  end

  it "falls back blank identities and ignores unresolved dependencies" do
    tasks = ir.items.select { |item| item.role == "task" }

    expect([ir.id, tasks.map(&:id), ir.connections,
            ir.accessibility_title, ir.accessibility_description])
      .to eq(["gantt", %w[task_0 task_1], [], nil, nil])
  end

  def task(id, dependency)
    Sirena::Diagram::GanttTask.new.tap do |item|
      item.id = id
      item.description = "Task"
      item.after_task = dependency
    end
  end
end
