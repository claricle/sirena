# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Gantt do
  subject(:scene) do
    diagram = Sirena::Parser::Gantt.new.parse(source)
    described_class.new.call(diagram, today: Date.new(2026, 10, 11))
  end

  let(:source) do
    File.read(
      File.join(__dir__, "../../mermaid/gantt/" \
                         "should_handle_a_dateformat_definition-16cdb290.mmd"),
    )
  end

  it "collapses the malformed explicit end onto the task start" do
    task = scene.sections.first.tasks.first

    expect([task.start_date, task.end_date]).to eq([Date.new(2014, 1, 1)] * 2)
  end

  it "does not invent yearly ticks through the injected current date" do
    expect(scene.timeline.labels.map(&:text)).to eq(["2014-01-01"])
  end
end
