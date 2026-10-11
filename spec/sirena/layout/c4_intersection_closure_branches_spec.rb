# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::C4Intersection do
  let(:box) do
    ->(x_pos, y_pos) { double(x: x_pos, y: y_pos, width: 100, height: 50) }
  end

  it "exits the bottom edge toward a centre directly below" do
    points = described_class.points(box.(50, 0), box.(0, 200))
    expect(points.first).to eq([100.0, 50])
  end

  it "exits the top edge toward a centre directly above" do
    points = described_class.points(box.(50, 300), box.(0, 0))
    expect(points.first).to eq([100.0, 300])
  end

  it "exits the left edge toward a level centre on the left" do
    points = described_class.points(box.(300, 25), box.(0, 0))
    expect(points.first).to eq([300, 50.0])
  end
end
