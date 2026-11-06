# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

RSpec.describe Sirena::Notation::PlantUML::NodeGraph::Packer do
  let(:items) { Array.new(3) { Object.new } }
  let(:sizes) { items.to_h { |item| [item, [40.0, 20.0]] } }
  let(:ranking) do
    first, second, third = items
    Sirena::Notation::PlantUML::NodeGraph::Ranking.new(
      items, [[first, second, 1], [second, third, 1], [first, third, 2]]
    )
  end
  let(:packer) { described_class.new(sizes, left_to_right: false) }
  let(:packed) { packer.route(packer.pack(ranking.layers), ranking.chains) }

  it "keeps a waypoint out of the offsets of what is placed" do
    expect(packed.offsets.keys).to match_array(items)
  end

  it "puts the point in the middle of its rank, beside what stands there",
     :aggregate_failures do
    point = packed.paths.fetch([items.first, items.last]).first
    second = packed.offsets.fetch(items[1])

    expect(point[1]).to eq(second[1] + 10.0)
    expect(point[0]).not_to be_between(second[0], second[0] + 40.0)
  end
end
