# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::C4Intersection do
  let(:box) do
    ->(x_pos, y_pos) { double(x: x_pos, y: y_pos, width: 100, height: 50) }
  end

  it "leaves a box through its bottom edge when the other centre is directly below" do
    points = described_class.points(box.(50, 0), box.(0, 200))
    expect(points.first).to eq([100.0, 50])
  end

  it "leaves a box through its top edge when the other centre is directly above" do
    points = described_class.points(box.(50, 300), box.(0, 0))
    expect(points.first).to eq([100.0, 300])
  end

  it "leaves a box from its left edge when the other centre is level and to the left" do
    points = described_class.points(box.(300, 25), box.(0, 0))
    expect(points.first).to eq([300, 50.0])
  end
end

RSpec.describe Sirena::Layout::C4Placement do
  let(:empty_boundary) do
    {
      width: 0, height: 0, children: [], header: 20,
      metadata: { boundary_type: "Boundary" }
    }
  end
  let(:graph) { { children: [empty_boundary, empty_boundary.dup], metadata: {} } }

  it "starts a boundary at the same x as an empty boundary beside it" do
    described_class.apply(graph)
    expect(graph[:children].map { |node| node[:x] }).to eq([150, 150])
  end
end
