# frozen_string_literal: true

RSpec.describe Sirena::Layout::FlowchartEdgeRouter do
  it "routes around the horizontal corridor of unequal overlapping clusters" do
    source = {
      x: 0, y: 10, width: 40, height: 20,
      metadata: { cluster: true }
    }
    target = {
      x: 10, y: 0, width: 100, height: 150,
      metadata: { cluster: true }
    }

    points, = described_class.new.route(source, target)
    intermediate_y = points[1...-1].map { |point| point[:y] }

    expect(intermediate_y).to eq([170, 170])
    expect(intermediate_y).to all(be > [source, target].map { |box| box[:y] + box[:height] }.max)
  end
end
