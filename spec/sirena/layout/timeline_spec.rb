# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Timeline do
  let(:source) do
    <<~MERMAID
      timeline
        title Launch history
        section History
        2020 : Started
        section Work
        Research
        Build
    MERMAID
  end
  let(:diagram) { Sirena::Parser::Timeline.new.parse(source) }
  let(:scene) { described_class.new.to_graph(diagram) }

  it "lays out shared pre-positioned IR identically to the private model" do
    diagram.acc_title = "Accessible history"
    diagram.acc_description = "Launches over time"
    ir = Sirena::Notation::Mermaid::IRAdapters::Timeline.call(diagram)
    actual = Marshal.dump(described_class.new.call(ir))

    expect(actual).to eq(Marshal.dump(scene))
  end

  describe "final geometry" do
    subject(:geometry_evidence) do
      history, work = scene.tracks
      actual = [scene.class, scene.width, scene.height, scene.view_box,
                [history.header.text, history.header.x, history.header.y],
                [history.axis.x, history.axis.y, history.axis.width],
                [history.entries.first.marker.x,
                 history.entries.first.marker.y],
                history.entries.first.labels.map do |label|
                  [label.text, label.x, label.y]
                end,
                [work.header.text, work.header.y, work.axis.y],
                work.entries.map do |entry|
                  [entry.marker.x, entry.marker.y, entry.labels.first.text]
                end]
      expected = [described_class::Scene, 960.0, 380.0, "0 0 960 380",
                  ["History", 80.0, 100.0], [80.0, 140.0, 800.0],
                  [480.0, 143.0],
                  [["Started", 480.0, 175.0], ["2020", 480.0, 125.0]],
                  ["Work", 160.0, 200.0],
                  [[346.6666666666667, 203.0, "Research"],
                   [613.3333333333334, 203.0, "Build"]]]

      [actual, expected]
    end

    it "returns typed final-canvas geometry for events and tasks" do
      expect(geometry_evidence.first).to eq(geometry_evidence.last)
    end
  end

  describe "theme typography" do
    subject(:typography_evidence) do
      theme = Sirena::Theme::Registry.get(:high_contrast)
      themed = described_class.new.call(diagram, theme: theme)
      actual = [themed.title.font_size,
                themed.tracks.first.header.font_size,
                themed.tracks.first.entries.first.labels.map(&:font_size)]
      expected = [theme.typography.font_size_large,
                  theme.typography.font_size_normal,
                  [theme.typography.font_size_small,
                   theme.typography.font_size_small]]

      [actual, expected]
    end

    it "stores theme typography in the scene" do
      expect(typography_evidence.first).to eq(typography_evidence.last)
    end
  end

  it "does not send its hand-laid-out scene through Grid" do
    calls = []
    allow(Sirena::Layout::Grid).to receive(:apply) { calls << :apply }

    result = described_class.new.call(diagram)

    expect([result.class, calls]).to eq([described_class::Scene, []])
  end
end
