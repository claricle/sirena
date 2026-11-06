# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

RSpec.describe Sirena::Notation::PlantUML::NodeGraph::LabelPlacer do
  let(:route_class) { Struct.new(:points, :edge, :label_at) }
  let(:edge_class) { Struct.new(:label, :width) }

  def route_on(points)
    route_class.new(points, edge_class.new("label"))
  end

  it "walks past a short leading segment to reach the label spot" do
    bent = route_on([[0, 0], [10, 0], [10, 100]])

    placement = described_class.new.call([bent]).first

    expect([placement.x - (placement.width / 2) > 10.0, placement.y])
      .to eq([true, 41.0])
  end

  it "keeps a label off the vertical edge it names" do
    placement = described_class.new.call([route_on([[0, 0], [0, 100]])]).first

    expect(placement.x - (placement.width / 2)).to be > 0.0
  end

  it "sets a label above a flat edge, clear of a thick stroke" do
    thick = route_class.new([[0, 50], [200, 50]], edge_class.new("label", 8))

    placement = described_class.new.call([thick]).first

    expect([placement.x, placement.bottom]).to eq([100.0, 45.0])
  end

  it "puts the label of an edge running down to the left below its middle" do
    placement = described_class.new.call([route_on([[100, 0], [0, 100]])])
      .first

    expect(placement.y).to be > 50.0
  end

  it "puts the label of an edge running down to the right above its middle" do
    placement = described_class.new.call([route_on([[0, 0], [100, 100]])])
      .first

    expect(placement.y).to be < 50.0
  end

  it "keeps a label off the nodes" do
    box = Sirena::Notation::PlantUML::NodeGraph::Placed
      .new(x: 4.0, y: 20.0, width: 80.0, height: 60.0)

    placement = described_class.new.call([route_on([[0, 0], [0, 100]])], [box])
      .first

    expect(clear_of_box?(placement)).to be(true)
  end

  def clear_of_box?(placement)
    left = placement.x - (placement.width / 2)
    [placement.right <= 4.0, left >= 84.0, placement.bottom <= 20.0,
     placement.y - 12.0 >= 80.0].any?
  end

  it "reports how far a label reaches" do
    placement = described_class.new.call([route_on([[0, 0], [0, 100]])]).first

    expect([placement.right, placement.bottom])
      .to eq([placement.x + (placement.width / 2) + 2.0, placement.y + 3.0])
  end

  it "keeps a label on the middle of its edge when every spot is taken" do
    routes = Array.new(300) { route_on([[0, 0], [0, 100]]) }

    placements = described_class.new.call(routes)

    expect([placements.size, placements.last.x, placements.last.y])
      .to eq([300, 0.0, 46.0])
  end

  it "prints a label to the right of the point its line passes through" do
    routed = route_class.new([[0, 0], [0, 100]], edge_class.new("label"),
                             [0.0, 50.0])

    placement = described_class.new.call([routed]).first

    expect(placement.x).to be > 0.0
  end

  it "keeps a label off the line of a neighbouring edge" do
    own = route_class.new([[0, 50], [200, 50]], edge_class.new("label", 1))
    across = route_class.new([[40, 40], [160, 40]], edge_class.new("", 1))

    placement = described_class.new.call([own, across]).first

    expect(placement.y - 12.0 > 40.0 || placement.bottom < 40.0).to be(true)
  end

  it "sets a label left of a steep edge when a neighbour fills its right" do
    own = route_class.new([[100, 0], [100, 200]], edge_class.new("label", 1),
                          [100.0, 100.0])
    wall = route_class.new([[120, -500], [120, 500]], edge_class.new("", 1))

    placement = described_class.new.call([own, wall]).first

    expect(placement.right).to be < 100.0
  end

  it "sets a label below a flat edge when a neighbour runs over it" do
    own = route_class.new([[0, 100], [300, 100]], edge_class.new("label", 1),
                          [150.0, 100.0])
    roof = route_class.new([[-500, 80], [500, 80]], edge_class.new("", 1))

    placement = described_class.new.call([own, roof]).first

    expect(placement.y - 12.0).to be > 100.0
  end

  it "keeps a label near its edge when the neighbours fill the space" do
    own = route_class.new([[0, 100], [300, 100]], edge_class.new("label", 1),
                          [150.0, 100.0])

    placement = described_class.new.call([own, *fence]).first

    expect((placement.y - 100.0).abs).to be < 30.0
  end

  def fence
    Array.new(31) do |index|
      route_class.new([[index * 10, -500], [index * 10, 500]],
                      edge_class.new("", 1))
    end
  end
end
