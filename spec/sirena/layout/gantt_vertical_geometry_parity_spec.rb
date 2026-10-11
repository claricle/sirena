# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Gantt, :aggregate_failures do
  subject(:scene) do
    diagram = Sirena::Parser::Gantt.new.parse(source)
    described_class.new.call(diagram, today: Date.new(2024, 1, 1))
  end

  let(:source) do
    <<~GANTT
      gantt
        dateFormat YYYY-MM-DD
        axisFormat %Y-%m-%d
        section Planning
        Design :design, 2024-01-01, 1d
        Build :build, 2024-01-02, 1d
        section Release
        Ship :ship, 2024-01-03, 1d
    GANTT
  end

  it "matches the pinned continuous task-row geometry" do
    bars = scene.sections.flat_map(&:tasks).map(&:bar)
    sections = scene.sections.map(&:background)
    grid = scene.timeline.grid_lines

    expect(bars.map(&:y)).to eq([122.0, 146.0, 170.0])
    expect(sections.map { |box| [box.y, box.height] })
      .to eq([[120.0, 48.0], [168.0, 24.0]])
    expect(grid.map { |line| [line.y1, line.y2] }.uniq)
      .to eq([[120.0, 192.0]])
    expect(scene.timeline.labels.map(&:y).uniq).to eq([197.0])
    expect(scene.height).to eq(242.0)
  end
end
