# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::C4Text do
  it "splits lines on break tags of either spelling" do
    expect(described_class.lines("a<br/>b <BR>c")).to eq(%w[a b c])
  end

  it "treats nil as one empty line" do
    expect(described_class.lines(nil)).to eq([""])
  end

  it "gives an empty line no height" do
    expect(described_class.height("", 16)).to eq(0)
  end

  it "uses the browser line height for 12, 14 and 16 px text" do
    heights = [12, 14, 16].map { |size| described_class.height("a", size) }
    expect(heights).to eq([14, 16, 17])
  end

  it "adds the height of every non-empty line" do
    expect(described_class.height("a<br/>b<br/>", 16)).to eq(34)
  end

  it "rounds the widest line to a whole pixel" do
    width = described_class.width("short<br/>a longer line", 14)
    measured = Sirena::TextMeasurement.measure("a longer line", font_size: 14)
    expect(width).to eq(measured[:width].round)
  end
end
