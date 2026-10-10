# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Gantt do
  let(:reference_date) { Date.new(2024, 1, 1) }

  it "omits the synthetic timeline when the diagram has no tasks" do
    sources = [
      "gantt",
      "gantt\ndateFormat YYYY-MM-DD",
      "gantt\nsection Planning",
    ]

    timelines = sources.map { |source| lay_out(source).timeline }

    expect(timelines).to all(be_nil)
  end

  it "keeps timeline geometry when the diagram has a task" do
    scene = lay_out(<<~GANTT)
      gantt
        section Planning
        Design :design, 2024-01-01, 2d
    GANTT

    expect([scene.timeline.background.kind, scene.timeline.labels.empty?])
      .to eq(["timeline", false])
  end

  def lay_out(source)
    diagram = Sirena::Parser::Gantt.new.parse(source)
    described_class.new.call(diagram, today: reference_date)
  end
end
