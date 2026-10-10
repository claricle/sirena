# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/gantt"

RSpec.describe Sirena::Notation::Mermaid::IRAdapters::Gantt do
  let(:task) do
    Sirena::Diagram::GanttTask.new.tap do |entry|
      entry.id = "build"
      entry.description = "Build"
      entry.after_task = "ghost"
    end
  end
  let(:diagram) do
    Sirena::Diagram::Gantt.new.tap do |gantt|
      gantt.id = "plan"
      gantt.sections = [Sirena::Diagram::GanttSection.new("S").tap do |sec|
        sec.tasks = [task]
      end]
    end
  end

  it "drops a dependency on a task that does not exist" do
    expect(described_class.call(diagram).connections).to be_empty
  end
end
