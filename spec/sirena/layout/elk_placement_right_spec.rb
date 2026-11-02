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
    placed_object(width: 84, height: 304, children: children, edges: [edge])
  end

  def apply_direction(value)
    right_graph[:layoutOptions][direction] = value
    described_class.apply(right_graph)
  end

  def capture_input
    sent = []
    allow(Elkrb).to receive(:layout) do |input|
      sent << input
      routed_result
    end
    sent
  end

  def box_sizes(input)
    input[:children].map { |box| box.values_at(:width, :height) }
  end

  def first_section(value)
    apply_direction(value)[:edges].first[:sections].first
  end

  def nested_graph(direction)
    source = "flowchart #{direction}\n subgraph S\n A-->B\n end\n"
    diagram = Sirena::Parser::Flowchart.new.parse(source)
    graph = Sirena::Notation::Mermaid::IRAdapters::Flowchart.call(diagram)
    Sirena::Layout::Flowchart.new.send(:build_graph, graph)
  end

  it "lays a real elkrb graph from left to right" do
    result = described_class.apply(right_graph)
    first, second = result[:children]
    expect([first[:x] < second[:x], first[:width], second[:height]])
      .to eq([true, 120.0, 60.0])
  end

  it "copies a rightward route as elkrb laid it" do
    allow(Elkrb).to receive(:layout).and_return(routed_result)
    section = first_section("RIGHT")
    expect(section).to eq(startPoint: { x: 23, y: 127 },
                          endPoint: { x: 43, y: 207 },
                          bendPoints: [{ x: 33, y: 167 }])
  end

  it "asks elkrb for the direction itself instead of turning the boxes" do
    sent = capture_input
    apply_direction("RIGHT")
    expect([sent.first[:layoutOptions][direction], box_sizes(sent.first)])
      .to eq(["RIGHT", [[120, 40], [80, 60]]])
  end

  it "keeps elkrb's downward placement, b centred under a" do
    right_graph[:layoutOptions][direction] = "DOWN"
    result = described_class.apply(right_graph)
    expect(geometry(result)).to eq([["a", 12.0, 12.0, 120.0, 40.0],
                                    ["b", 32.0, 132.0, 80.0, 60.0]])
  end

  it "lays a real elkrb graph from bottom to top" do
    first, second = apply_direction("UP")[:children]
    expect([first[:y] > second[:y], first[:height], second[:width]])
      .to eq([true, 40.0, 80.0])
  end

  it "copies an upward route as elkrb laid it" do
    allow(Elkrb).to receive(:layout).and_return(routed_result)
    expect(first_section("UP"))
      .to eq(startPoint: { x: 23, y: 127 },
             endPoint: { x: 43, y: 207 }, bendPoints: [{ x: 33, y: 167 }])
  end

  it "lays a real elkrb graph from right to left" do
    first, second = apply_direction("LEFT")[:children]
    expect([first[:x] > second[:x], first[:width], second[:height]])
      .to eq([true, 120.0, 60.0])
  end

  it "copies a leftward route as elkrb laid it" do
    allow(Elkrb).to receive(:layout).and_return(routed_result)
    expect(first_section("LEFT"))
      .to eq(startPoint: { x: 23, y: 127 },
             endPoint: { x: 43, y: 207 }, bendPoints: [{ x: 33, y: 167 }])
  end

  it "keeps reversed compound nodes in the positive root frame" do
    graphs = %w[BT RL].map do |value|
      described_class.apply(nested_graph(value))
    end
    origins = graphs.map { |graph| graph[:children].first.values_at(:x, :y) }
    expect(origins.flatten).to all(be >= 0)
  end
end
