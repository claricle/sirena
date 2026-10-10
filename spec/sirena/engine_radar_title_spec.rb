# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Engine do
  subject(:texts) do
    svg = described_class.new.render(source)
    svg.scan(%r{<text[^>]*>([^<]*)</text>}).flatten
  end

  context "with a radar that has a title" do
    let(:source) do
      "radar-beta\n  title Best Radar Ever\n  axis A, B, C\n  " \
        "curve c1{1, 2, 3}\n"
    end

    it "draws the title after the axis and legend labels" do
      expect(texts).to eq(["A", "B", "C", "c1", "Best Radar Ever"])
    end
  end

  context "with a radar that has no title" do
    let(:source) { "radar-beta\n  axis A, B, C\n  curve c1{1, 2, 3}\n" }

    it "draws no title" do
      expect(texts).to eq(["A", "B", "C", "c1"])
    end
  end
end
