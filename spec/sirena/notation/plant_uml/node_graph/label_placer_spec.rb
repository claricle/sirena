# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

RSpec.describe Sirena::Notation::PlantUML::NodeGraph::LabelPlacer do
  let(:route_class) { Struct.new(:points, :edge) }
  let(:edge_class) { Struct.new(:label) }

  def route_on(points)
    route_class.new(points, edge_class.new("label"))
  end

  it "walks past a short leading segment to reach the label spot" do
    bent = route_on([[0, 0], [10, 0], [10, 100]])

    placement = described_class.new.call([bent]).first

    expect([placement.x, placement.y]).to eq([10.0, 41.0])
  end

  it "keeps a label on the middle of its edge when every spot is taken" do
    routes = Array.new(300) { route_on([[0, 0], [0, 100]]) }

    placements = described_class.new.call(routes)

    expect([placements.size, placements.last.x, placements.last.y])
      .to eq([300, 0.0, 46.0])
  end
end
