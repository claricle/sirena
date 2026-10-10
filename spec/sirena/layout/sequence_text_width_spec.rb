# frozen_string_literal: true

require "spec_helper"

# Widths are what mmdc's getBBox returned in headless Chrome for the same
# 16px text (Times New Roman, the browser default): 160.41 and 251.9.
RSpec.describe Sirena::Layout::Sequence::TextWidth do
  {
    "Hello Bob, how are you?" => 160,
    "I #9829; you #infin; times more!" => 252,
  }.each do |text, width|
    it "measures #{text.inspect} as #{width}" do
      expect(described_class.of(text, 16)).to eq(width)
    end
  end

  it "does not count leading and trailing spaces" do
    expect(described_class.of("  hi  ", 16)).to eq(
      described_class.of("hi", 16),
    )
  end

  it "folds a run of spaces into one" do
    expect(described_class.of("a   b", 16)).to eq(
      described_class.of("a b", 16),
    )
  end

  it "measures a reference in its encoded form, not as the symbol" do
    expect(described_class.of("#9829;", 16)).to be > 60
  end

  it "takes the widest of several lines" do
    expect(described_class.widest(["a", "a much longer line"], 16)).to eq(
      described_class.of("a much longer line", 16),
    )
  end

  it "is 0 for no lines" do
    expect(described_class.widest([], 16)).to eq(0)
  end

  it "falls back to Arial for a character the table lacks" do
    expect(described_class.of("中", 16)).to be > 0
  end

  it "scales with the font size" do
    expect(described_class.of("Hello", 32)).to eq(71)
  end
end
