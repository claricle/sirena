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

  it "rounds a width of 184.976 up to the whole pixel" do
    expect(described_class.width("Banking System G Queue", 16)).to eq(185)
  end

  it "takes the widest of several lines" do
    wide = described_class.width("Banking System G Queue", 16)
    expect(described_class.width("a<br/>Banking System G Queue", 16))
      .to eq(wide)
  end
end
