# frozen_string_literal: true

require "spec_helper"
require "sirena/layout/mindmap_node_size"

RSpec.describe Sirena::Layout::MindmapNodeSize do
  subject(:size) { described_class.method(:call) }

  let(:kerned_boxes) do
    {
      ["Round rectangle", "round"] => 146.2635625,
      ["Root", "round"] => 62.1835625,
      ["Popularisation", "default"] => 141.426,
      ["Research", "default"] => 103.8635625,
      ["On Automatic creation", "default"] => 201.3571875,
      ["Tools", "default"] => 75.6878125,
      ["Pen and paper", "default"] => 142.482,
    }
  end

  it "applies the target fixtures' Trebuchet pairs before node padding" do
    widths = kerned_boxes.keys.to_h do |label, shape|
      [[label, shape], size.call(label, shape)[:width]]
    end

    expect(widths).to eq(kerned_boxes)
  end

  it "includes the space pair in the wrapped Tony Buzan label" do
    adjustment = Sirena::TextMeasurement::TrebuchetKerning.adjustment(
      "author Tony Buzan", font_size: 16
    )

    expect(adjustment).to eq(-2.28125)
  end

  it "keeps the empirical bang and cloud fits unchanged" do
    expect([size.call("Tools", "bang")[:width],
            size.call("Tools", "cloud")[:width]])
      .to eq([109.5, 76.3832])
  end
end
