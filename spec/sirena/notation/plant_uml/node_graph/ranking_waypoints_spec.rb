# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

RSpec.describe Sirena::Notation::PlantUML::NodeGraph::Ranking do
  let(:items) { Array.new(3) { Object.new } }
  let(:ranking) do
    first, second, third = items
    described_class.new(items, [[first, second, 1], [second, third, 1],
                                [first, third, 2]])
  end

  it "gives a link that skips a rank a waypoint in it", :aggregate_failures do
    waypoints = ranking.chains.fetch([items.first, items.last])

    expect(waypoints.size).to eq(1)
    expect(ranking.layers[1]).to include(waypoints.first)
  end

  describe "a link that starts in a later rank than the first" do
    let(:other) { Object.new }
    let(:ranked) do
      first, second, third = items
      described_class.new(items + [other],
                          [[first, second, 1], [second, third, 1],
                           [other, third, 2]])
    end

    it "orders its waypoint beside what its own link leaves" do
      waypoint = ranked.chains.fetch([other, items.last]).first

      expect(ranked.layers[1].index(waypoint))
        .to be > ranked.layers[1].index(items[1])
    end
  end

  it "adds none for a link of one rank" do
    first, second = items
    ranked = described_class.new([first, second], [[first, second, 1]])

    expect(ranked.chains).to be_empty
  end
end
