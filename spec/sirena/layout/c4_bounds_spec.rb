# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::C4Bounds do
  subject(:bounds) { described_class.new(width_limit: 800, per_row: 4) }

  let(:nodes) { Array.new(5) { { width: 216, height: 60 } } }

  before { bounds.start_at(50, 10) }

  def finished_child
    described_class.new(width_limit: 800, per_row: 4).tap do |child|
      child.start_at(0, 0)
      child.data.stopx = 100
      child.data.stopy = 200
    end
  end

  def positions
    nodes.each { |node| bounds.insert(node) }
    nodes.map { |node| [node[:x], node[:y]] }
  end

  it "puts the first box 50 right and 100 below the start" do
    expect(positions.first).to eq([100, 110])
  end

  it "puts the second box beside the first with a 100 gap" do
    expect(positions[1]).to eq([416, 110])
  end

  it "starts a new row when the next box would pass the limit" do
    expect(positions[2]).to eq([100, 270])
  end

  it "wraps after per_row boxes even when there is room" do
    wide = described_class.new(width_limit: 5000, per_row: 2)
    wide.start_at(50, 10)
    rows = nodes.each { |node| wide.insert(node) }.map { |node| node[:y] }
    expect(rows).to eq([110, 110, 270, 270, 430])
  end

  it "grows the extent over every box" do
    positions
    data = bounds.data
    expect([data.startx, data.starty, data.stopx, data.stopy])
      .to eq([50, 10, 632, 490])
  end

  it "adds a margin to the extent after the last box" do
    bounds.insert(nodes.first)
    bounds.bump_last_margin
    expect([bounds.data.stopx, bounds.data.stopy]).to eq([366, 220])
  end

  it "absorbs a finished child plus a margin" do
    bounds.absorb(finished_child)
    expect([bounds.data.stopx, bounds.data.stopy]).to eq([150, 250])
  end
end
