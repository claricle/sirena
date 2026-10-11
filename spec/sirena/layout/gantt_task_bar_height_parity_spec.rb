# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "rexml/xpath"

RSpec.describe Sirena::Layout::Gantt do
  subject(:task_evidence) do
    bar = task.bar
    [bar.height, bar.y + (bar.height / 2), task.start_date, task.end_date]
  end

  let(:source_name) { "should_handle_a_task_definition-09f6496b" }
  let(:source) { File.read("spec/mermaid/gantt/#{source_name}.mmd") }
  let(:scene) do
    diagram = Sirena::Parser::Gantt.new.parse(source)
    described_class.new.call(diagram)
  end
  let(:task) { scene.sections.flat_map(&:tasks).first }

  it "matches the pinned task height without moving or rescheduling it" do
    expect(task_evidence).to eq(expected_task_evidence)
  end

  def expected_task_evidence
    [reference_task_height, 170.0,
     Date.new(2014, 1, 1), Date.new(2014, 1, 4)]
  end

  def reference_task_height
    path = "spec/fixtures_mermaid/gantt/#{source_name}.svg"
    document = REXML::Document.new(File.read(path))
    task_rect = REXML::XPath.match(document, "//rect").find do |rect|
      rect.attributes["class"].to_s.split.include?("task")
    end
    task_rect.attributes["height"].to_f
  end
end
