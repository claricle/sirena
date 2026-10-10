# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Engine do
  subject(:texts) do
    svg = described_class.new.render(source)
    svg.scan(%r{<text[^>]*>([^<]*)</text>}).flatten
  end

  context "with a pie without showData" do
    let(:source) { "pie\n\"ash\": 60\n\"oak\": 40\n" }

    it "draws integer percent slice labels and bare legend labels" do
      expect(texts).to eq(["60%", "40%", "ash", "oak"])
    end
  end

  context "with a pie under showData" do
    let(:source) { "pie showData\n\"ash\": 60\n\"oak\": 40\n" }

    it "adds the value to the legend text only" do
      expect(texts).to eq(["60%", "40%", "ash [60]", "oak [40]"])
    end
  end
end
