# frozen_string_literal: true

require "spec_helper"
require_relative "activity_helpers"

RSpec.describe Sirena::Notation::PlantUML::Activity::RowSpread do
  let(:a) { [-1, 0] }
  let(:b) { [-1, 1] }
  let(:c) { [-1, 2] }
  let(:widths) { { a => [10.0, 10.0], b => [10.0, 10.0], c => [10.0, 10.0] } }

  def spread(rows)
    described_class.new(rows, widths, 5.0).call([a, b, c]) { 20.0 }
  end

  it "clears the reach of the rows two columns share, and a gap" do
    rows = { a => { 0 => [10.0, 30.0] }, b => { 0 => [8.0, 10.0] },
             c => { 5 => [10.0, 10.0] } }

    expect(spread(rows)[b]).to eq(15.0 + 30.0 + 8.0 + 20.0)
  end

  it "lets a column reach under another that shares no row",
     :aggregate_failures do
    rows = { a => { 0 => [10.0, 30.0] }, b => { 1 => [8.0, 10.0] },
             c => { 2 => [10.0, 10.0] } }
    placed = spread(rows)

    expect(placed[b]).to eq(placed[a])
    expect(placed[c]).to eq(placed[b])
  end

  it "keeps a column left of nothing and off the margin" do
    rows = { a => { 0 => [1.0, 1.0] }, b => { 1 => [1.0, 1.0] },
             c => { 2 => [1.0, 1.0] } }

    expect(spread(rows).values.min).to eq(15.0)
  end
end
