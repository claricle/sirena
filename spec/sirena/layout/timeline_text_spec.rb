# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::TimelineText do
  # Wrapped lines below are the tspans mmdc draws for the same text.
  {
    "Machinery, Water power, Steam <br>power" =>
      ["Machinery, Water", "power, Steam", "power"],
    "Electricity, Internal combustion engine, Mass production" =>
      ["Electricity, Internal", "combustion engine,", "Mass production"],
    "Artificial intelligence, Big data,3D printing" =>
      ["Artificial", "intelligence, Big", "data,3D printing"],
    "Internet, Robotics, Internet of Things" =>
      ["Internet, Robotics,", "Internet of Things"],
  }.each do |text, lines|
    it "wraps #{text.inspect} as mmdc does" do
      expect(described_class.wrap(text, 150)).to eq(lines)
    end
  end

  it "breaks a line at a <br> even when the text fits" do
    expect(described_class.wrap("a<br>b", 150)).to eq(%w[a b])
  end

  it "collapses runs of whitespace" do
    expect(described_class.wrap("a    b", 150)).to eq(["a b"])
  end

  it "keeps an over-long word on a line of its own" do
    expect(described_class.wrap("x #{'w' * 40} y", 150).length).to eq(3)
  end

  it "sizes a one line card at 47.8, a period's 67.8 minus 20" do
    expect(described_class.card_height(["task1"])).to be_within(0.001)
      .of(47.8)
  end

  it "adds 17.6 for each further line" do
    heights = [%w[a], %w[a b]].map { |l| described_class.card_height(l) }

    expect(heights.reduce(:-).abs).to be_within(0.001).of(17.6)
  end

  it "does not count blank lines as drawn text" do
    expect(described_class.text_height(["", "a"])).to eq(19.0)
  end
end
