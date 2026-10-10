# frozen_string_literal: true

require "spec_helper"
require "sirena/layout/mindmap_node_size"

RSpec.describe Sirena::Layout::MindmapNodeSize do
  # Sizes read off the mmdc reference SVGs in spec/fixtures_mermaid/mindmap.
  # The text width is mmdc's own 29.734; ours is the Arial table's 27.568.
  def size(label, shape)
    described_class.call(label, shape)
  end

  def text_width(label)
    Sirena::TextMeasurement.measure(label, font_size: 16)[:width]
  end

  it "pads a default node by 40 across and 10 down" do
    expect(size("root", "default"))
      .to include(width: text_width("root") + 40, height: 34.0)
  end

  it "pads a square node by 40 across and 20 down" do
    expect(size("root", "square"))
      .to include(width: text_width("root") + 40, height: 44.0)
  end

  it "pads a round node by 30 across and 30 down" do
    expect(size("root", "round"))
      .to include(width: text_width("root") + 30, height: 54.0)
  end

  it "pads a circle by 20 around its longer side" do
    side = text_width("root") + 20

    expect(size("root", "circle")).to include(width: side, height: side)
  end

  it "stacks a <br> line break as two 24px lines" do
    expect(size("one<br/>two", "default")).to include(height: 58.0)
  end

  it "wraps a label wider than 200px at 200px" do
    label = "A root with a long text that wraps to keep the node size in check"

    expect(size(label, "default")).to include(width: 240.0, height: 82.0)
  end

  it "returns the wrapped lines" do
    label = "A root with a long text that wraps to keep the node size in check"

    expect(size(label, "default")[:lines].length).to eq(3)
  end

  it "keeps an unbreakable word whole and sizes the box to it" do
    word = "x" * 60

    expect(size(word, "default")[:lines]).to eq([word])
  end

  it "drops blank lines and surrounding whitespace" do
    expect(size("  \n  The root\n  ", "default")[:lines]).to eq(["The root"])
  end

  it "keeps an all-blank label as one renderable line" do
    expect(size("  \n  ", "default")[:lines]).to eq([""])
  end

  it "falls back to the default box for an unknown shape" do
    expect(size("root", "mystery")).to eq(size("root", "default"))
  end

  # mmdc box of "the root" per shape: hexagon, bang, cloud.
  {
    "hexagon" => [126.4, 44.0],
    "bang" => [135.5, 80.0],
    "cloud" => [91.7, 66.9],
  }.each do |shape, (wide, high)|
    it "sizes a #{shape} within 5% of mmdc" do
      box = size("the root", shape)

      expect([box[:width] / wide, box[:height] / high])
        .to all(be_within(0.05).of(1.0))
    end
  end
end
