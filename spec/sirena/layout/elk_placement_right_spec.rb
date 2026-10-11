# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::ElkPlacement do
  let(:elk_options) { Sirena::Layout::Base::ElkOptions }
  let(:direction) { elk_options::DIRECTION }
  let(:right_graph) do
    {
      children: [
        { id: "a", width: 120, height: 40 },
        { id: "b", width: 80, height: 60 },
      ],
      edges: [{ id: "a_b", sources: ["a"], targets: ["b"] }],
      layoutOptions: {
        direction => "RIGHT",
        elk_options::NODE_NODE_SPACING => 20,
        elk_options::LAYER_SPACING => 80,
      },
    }
  end

  def geometry(graph)
    graph[:children].map do |node|
      node.values_at(:id, :x, :y, :width, :height)
    end
  end

  def placed_object(**attributes)
    Struct.new(*attributes.keys, keyword_init: true).new(**attributes)
  end

  def routed_result
    point = Elkrb::Geometry::Point
    section = placed_object(
      start_point: point.new(x: 23, y: 127),
      end_point: point.new(x: 43, y: 207),
      bend_points: [point.new(x: 33, y: 167)],
    )
    edge = placed_object(id: "a_b", sections: [section])
    children = [
      placed_object(x: 3, y: 7, width: 40, height: 120,
                    children: [], edges: []),
      placed_object(x: 13, y: 207, width: 60, height: 80,
                    children: [], edges: []),
    ]
    placed_object(children: children, edges: [edge])
  end

  it "lays a real elkrb graph from left to right" do
    result = described_class.apply(right_graph)
    first, second = result[:children]
    expect([first[:x] < second[:x], first[:width], second[:height]])
      .to eq([true, 120.0, 60.0])
  end

  it "transposes every routed edge coordinate" do
    allow(Elkrb).to receive(:layout).and_return(routed_result)
    section = described_class.apply(right_graph)[:edges].first[:sections].first
    expect(section).to eq(startPoint: { x: 127, y: 23 },
                          endPoint: { x: 207, y: 43 },
                          bendPoints: [{ x: 167, y: 33 }])
  end

  it "preserves downward placement exactly" do
    right_graph[:layoutOptions][direction] = "DOWN"
    result = described_class.apply(right_graph)
    expect(geometry(result)).to eq([["a", 12.0, 12.0, 120.0, 40.0],
                                    ["b", 12.0, 132.0, 80.0, 60.0]])
  end

  it "rejects unsupported upward placement" do
    right_graph[:layoutOptions][direction] = "UP"
    expect { described_class.apply(right_graph) }
      .to raise_error(Sirena::Layout::LayoutError, /direction UP/)
  end

  it "rejects unsupported leftward placement" do
    right_graph[:layoutOptions][direction] = "LEFT"
    expect { described_class.apply(right_graph) }
      .to raise_error(Sirena::Layout::LayoutError, /direction LEFT/)
  end
end
