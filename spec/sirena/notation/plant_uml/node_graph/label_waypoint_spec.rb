# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

RSpec.describe Sirena::Notation::PlantUML::NodeGraph::LabelWaypoint do
  it "puts a point nearer the target than the source, mid rank" do
    point = described_class.through([[200.0, 0.0], [0.0, 100.0]], 1)

    expect(point).to eq([60.0, 50.0])
  end

  it "ignores a link that runs almost straight" do
    expect(described_class.through([[5.0, 0.0], [0.0, 100.0]], 1)).to be_nil
  end

  it "ignores a link with bends of its own" do
    points = [[0.0, 0.0], [90.0, 50.0], [0.0, 100.0]]

    expect(described_class.through(points, 1)).to be_nil
  end
end
