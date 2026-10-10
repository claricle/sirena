# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::KanbanCardText do
  def texts(text, width: 160)
    lines = described_class.lines(text, width: width, font_size: 14)
    lines.map { |runs| runs.map(&:text).join }
  end

  it "keeps a short label on one line" do
    expect(texts("Todo")).to eq(["Todo"])
  end

  it "wraps at word boundaries" do
    expect(texts("Create Blog about the new diagram"))
      .to eq(["Create Blog about the", "new diagram"])
  end

  it "keeps every word of a long title" do
    text = "Title of diagram is more than 100 chars when user duplicates"
    expect(texts(text).join(" ")).to eq(text)
  end

  it "splits a word wider than the width by character" do
    expect(texts("x" * 40).join).to eq("x" * 40)
  end

  it "keeps hard line breaks as separate lines" do
    expect(texts("One\nTwo")).to eq(%w[One Two])
  end

  it "keeps bold on the wrapped run" do
    runs = described_class.lines("**#{(['word'] * 10).join(' ')}**", width: 160, font_size: 14)

    expect(runs.flatten.map(&:bold)).to all(be(true))
  end
end
