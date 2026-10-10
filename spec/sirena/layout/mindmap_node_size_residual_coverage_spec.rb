# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::MindmapNodeSize, ".call" do
  it "keeps an all-blank label as one renderable line" do
    result = described_class.call("  \n  ", "default")

    expect(result[:lines]).to eq([""])
  end
end
