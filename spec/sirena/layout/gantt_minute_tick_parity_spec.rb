# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Gantt do
  let(:source) do
    <<~MERMAID
      gantt
        dateFormat YYYY-MM-DD
        axisFormat %H:%M
        tickInterval 30minute
        section S
        Task :a, 2024-01-31, 2h
    MERMAID
  end
  let(:diagram) { Sirena::Notation::Mermaid.parse(source).diagram }
  let(:scene) { described_class.new.call(diagram) }

  it "honors Mermaid's explicit half-hour tick interval" do
    labels = scene.timeline.labels.map(&:text)

    expect([labels, scene.timeline.grid_lines.length]).to eq(
      [["00:00", "00:30", "01:00", "01:30", "02:00"], 5],
    )
  end
end
