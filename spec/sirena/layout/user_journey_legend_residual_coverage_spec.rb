# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::UserJourneyLegend, "#rows" do
  it "does not render a blank line for trailing whitespace at the wrap width" do
    label = "x" * 45
    rows = described_class.new(["#{label} "]).rows

    expect(rows.first[3]).to eq([label])
  end
end
