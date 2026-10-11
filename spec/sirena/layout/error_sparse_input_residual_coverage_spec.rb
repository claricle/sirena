# frozen_string_literal: true

require "spec_helper"
require "sirena/layout/error"

RSpec.describe Sirena::Layout::Error do
  let(:theme_without_typography) { Sirena::Theme.new(name: "partial") }
  let(:theme_with_zero_size) do
    typography = Struct.new(:font_size_base).new(0)
    Struct.new(:typography).new(typography)
  end

  it "defaults a sparse shared error panel to the public error message" do
    data = Sirena::IR::Data.new(id: "failure", role: "error_panel")

    scene = described_class.new.call(data)

    expect([scene.id, scene.label.text]).to eq(["failure", "Error"])
  end

  it "keeps error text readable for partial and nonpositive themes" do
    sizes = [theme_without_typography, theme_with_zero_size].map do |theme|
      described_class.from_graph({}, theme: theme).label.font_size
    end

    expect(sizes).to eq([16.0, 16.0])
  end
end
