# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Appearance do
  it "keeps absent settings and applies supplied settings" do
    base = described_class.new(alignment: :left, tab_fill: "old")
    merged = base.merge(described_class.new(alignment: nil, tab_fill: "new"))
    expect([merged.alignment, merged.tab_fill]).to eq([:left, "new"])
  end
end
