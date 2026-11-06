# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

RSpec.describe Sirena::Notation::PlantUML::RelationPathPoints do
  it "follows the ends of straight lines" do
    expect(described_class.call("M 0 0 L 10 0 L 10 20"))
      .to eq([[0.0, 0.0], [10.0, 0.0], [10.0, 20.0]])
  end

  it "runs a cubic curve from its start to its end" do
    points = described_class.call("M 0 0 C 0 10 10 10 10 0")

    expect([points.first, points.last, points[8]])
      .to eq([[0.0, 0.0], [10.0, 0.0], [5.0, 7.5]])
  end

  it "runs a quadratic curve through its middle" do
    points = described_class.call("M 0 0 Q 10 20 20 0")

    expect(points[8]).to eq([10.0, 10.0])
  end

  it "has no points for a missing path" do
    expect(described_class.call(nil)).to eq([])
  end

  it "finds the point a share of the way along a polyline" do
    line = [[0.0, 0.0], [10.0, 0.0], [10.0, 10.0]]

    expect(described_class.along(line, 0.75)).to eq([10.0, 5.0])
  end

  it "ends a polyline at its last point when the share runs past it" do
    expect(described_class.along([[0.0, 0.0], [4.0, 0.0]], 1.5))
      .to eq([4.0, 0.0])
  end

  it "stays on the one point of a polyline without length" do
    expect(described_class.along([[3.0, 3.0]], 0.5)).to eq([3.0, 3.0])
  end

  it "stays on a point a zero-length leg starts at" do
    expect(described_class.along([[1.0, 1.0], [1.0, 1.0]], 0.0))
      .to eq([1.0, 1.0])
  end
end
