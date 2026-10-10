# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::UserJourneyLegend do
  let(:sentence) { Array.new(30, "word").join(" ") }
  let(:cut) { JourneyLegendLines.of("x" * 100) }

  describe "#rows" do
    it "lists actors alphabetically, once each" do
      rows = described_class.new(%w[Bob Al Bob]).rows

      expect(rows.map(&:first)).to eq(%w[Al Bob])
    end

    it "starts at y=60 and steps 20px per single-line row" do
      rows = described_class.new(%w[Al Bob]).rows

      expect(rows.map { |row| row[2] }).to eq([60, 80])
    end

    it "keeps a short name on one line" do
      expect(JourneyLegendLines.of("Alice")).to eq(["Alice"])
    end

    it "keeps a name of 352px, just under the wrap width, on one line" do
      expect(JourneyLegendLines.of("x" * 44).length).to eq(1)
    end

    it "keeps an empty name as one empty line" do
      expect(JourneyLegendLines.of("")).to eq([""])
    end

    it "wraps a long name on spaces" do
      expect(JourneyLegendLines.of(sentence).length).to eq(4)
    end

    it "wraps without losing words" do
      expect(JourneyLegendLines.of(sentence).join(" ")).to eq(sentence)
    end

    it "keeps every wrapped line within 360px" do
      widths = JourneyLegendLines.of(sentence).map do |line|
        JourneyLegendLines.width(line)
      end

      expect(widths.max).to be <= 360
    end

    it "grows the row by 20px per extra line" do
      rows = described_class.new([sentence, "z"]).rows

      expect(rows.last[2]).to eq(60 + (4 * 20))
    end

    it "cuts an overlong word with a hyphen" do
      expect(cut.first).to end_with("x-")
    end

    it "keeps a hyphen-cut line within 360px" do
      expect(JourneyLegendLines.width(cut.first)).to be <= 360
    end

    it "carries the rest of the cut word onto the next line" do
      expect(cut.sum { |line| line.delete("-").size }).to eq(100)
    end
  end

  describe "#left_margin" do
    it "is 150 when the widest line is at most 75px" do
      expect(described_class.new(["x" * 9]).left_margin).to eq(150)
    end

    it "adds the widest line once it is over 75px" do
      expect(described_class.new(["x" * 10]).left_margin).to eq(230)
    end

    it "uses the widest line of several actors" do
      margin = described_class.new(["x" * 10, "x" * 20]).left_margin

      expect(margin).to eq(310)
    end

    it "is 150 with no actors" do
      expect(described_class.new([]).left_margin).to eq(150)
    end
  end
end
