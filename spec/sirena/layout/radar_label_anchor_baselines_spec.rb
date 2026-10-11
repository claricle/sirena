# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Radar, "#call" do
  let(:source) do
    <<~MERMAID
      radar-beta
        title Baselines
        axis A, B, C
        curve first{1, 2, 3}
        curve second{3, 2, 1}
    MERMAID
  end
  let(:diagram) { Sirena::Parser::Radar.new.parse(source) }

  it "keeps Mermaid label anchors independent of font size" do
    regular = described_class.new.call(diagram)
    contrast = described_class.new.call(
      diagram, theme: Sirena::Theme::Registry.get(:high_contrast)
    )
    expected = [0.0, 35.0, 507.5, 507.5, 87.5, 107.5]

    expect([label_y(regular), label_y(contrast)]).to eq([expected, expected])
  end

  def label_y(scene)
    [scene.title.y, *scene.axes.map { |axis| axis.label.y },
     *scene.legend.map { |entry| entry.label.y }]
  end
end
