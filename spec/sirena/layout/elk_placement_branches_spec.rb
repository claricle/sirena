# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::ElkPlacement do
  let(:placed_node) do
    Struct.new(:x, :y, :width, :height, :children, :edges, keyword_init: true)
  end
  let(:spacing_graph) do
    spacing_key = Sirena::Layout::Base::ElkOptions::NODE_NODE_SPACING
    { layoutOptions: { spacing_key => 18 } }
  end
  let(:nested_case) do
    options = Sirena::Layout::Base::ElkOptions
    nested = { id: "nested" }
    parent = { id: "parent", children: [nested] }
    graph = {
      layoutOptions: {
        options::DIRECTION => "DOWN",
        options::NODE_NODE_SPACING => 12,
        options::LAYER_SPACING => 34,
      },
      children: [parent],
    }
    placed_nested = placed_node.new(
      x: 5.0,
      y: 6.0,
      width: 7.0,
      height: 8.0,
      children: nil,
    )
    placed_parent = placed_node.new(
      x: 1.0,
      y: 2.0,
      width: 3.0,
      height: 4.0,
      children: [placed_nested],
    )
    expected = [
      {
        id: "parent",
        children: [nested],
        x: 1.0,
        y: 2.0,
        width: 3.0,
        height: 4.0,
      },
      { id: "nested", x: 5.0, y: 6.0, width: 7.0, height: 8.0 },
    ]

    {
      graph: graph,
      nodes: [parent, nested],
      placed: placed_node.new(children: [placed_parent]),
      expected: expected,
    }
  end
  let(:self_loop_case) do
    loop_edge = { id: "loop", sources: ["A"], targets: ["A"] }
    routed_edge = { id: "routed", sources: ["A"], targets: ["B"] }
    edges = [loop_edge, routed_edge]
    { graph: { children: [], edges: edges }, edges: edges,
      routed_edge: routed_edge }
  end
  let(:edge_section_case) do
    labels = [{ text: "kept" }]
    metadata = { arrow_type: "arrow" }
    existing = [{ bendPoints: [{ x: 8, y: 9 }] }]
    graph = {
      children: [],
      edges: [
        { id: "first", labels: labels, metadata: metadata },
        { id: "second", sections: existing },
      ],
    }
    point = Elkrb::Geometry::Point
    section = Elkrb::Graph::EdgeSection.new(
      start_point: point.new(x: 1, y: 2),
      end_point: point.new(x: 5, y: 6),
      bend_points: [point.new(x: 3, y: 4)],
    )
    result = placed_node.new(
      children: nil,
      edges: [
        Elkrb::Graph::Edge.new(id: "second", sections: []),
        Elkrb::Graph::Edge.new(id: "first", sections: [section]),
      ],
    )
    expected = {
      id: "first", labels: labels, metadata: metadata,
      sections: [{ startPoint: { x: 1.0, y: 2.0 },
                   endPoint: { x: 5.0, y: 6.0 },
                   bendPoints: [{ x: 3.0, y: 4.0 }] }]
    }
    { graph: graph, result: result, expected: expected, existing: existing }
  end

  # The input elkrb 2 receives: one argument, whose layoutOptions carry
  # the direction and spacing.
  def capture_layout(result)
    received = []
    allow(Elkrb).to receive(:layout) do |*arguments|
      received.replace(arguments)
      result
    end
    received
  end

  def levels(input)
    [input, *Array(input[:children]).flat_map { |child| levels(child) }]
  end

  def nested_options
    options = Sirena::Layout::Base::ElkOptions
    layout_options(options::NODE_NODE_SPACING => 12,
                   options::LAYER_SPACING => 34)
  end

  def layout_options(overrides = {})
    options = Sirena::Layout::Base::ElkOptions
    {
      options::MODEL_ORDER => "NODES_AND_EDGES",
      options::DIRECTION => "DOWN",
      "elk.alignment" => "TOP",
      "elk.separateConnectedComponents" => false,
      options::CROSSING_MINIMIZATION => "NONE",
    }.merge(overrides)
  end

  def edge_section_result(graph, existing)
    [graph[:edges].first, graph[:edges].last[:sections].equal?(existing)]
  end

  it "lays out downward, top-aligned, in model order for a bare graph" do
    received = capture_layout(placed_node.new(children: nil))
    described_class.apply({})

    expect(received.map { |input| input[:layoutOptions] })
      .to eq([layout_options])
  end

  it "returns the graph it was given" do
    graph = {}
    capture_layout(placed_node.new(children: nil))

    expect(described_class.apply(graph)).to equal(graph)
  end

  it "leaves out a spacing the graph does not set" do
    received = capture_layout(placed_node.new(children: nil))
    described_class.apply(spacing_graph)
    spacing = Sirena::Layout::Base::ElkOptions::NODE_NODE_SPACING

    expect(received.map { |input| input[:layoutOptions] })
      .to eq([layout_options(spacing => 18)])
  end

  it "passes direction and spacing to every level" do
    received = capture_layout(nested_case[:placed])
    described_class.apply(nested_case[:graph])

    expect(levels(received.first).map { |level| level[:layoutOptions] }.uniq)
      .to eq([nested_options])
  end

  it "copies nested positions" do
    capture_layout(nested_case[:placed])
    described_class.apply(nested_case[:graph])

    expect(nested_case[:nodes]).to eq(nested_case[:expected])
  end

  it "removes only self-loops from elkrb input and retains original edges" do
    received = capture_layout(placed_node.new(children: nil))
    described_class.apply(self_loop_case[:graph])
    actual = [received.size, received.dig(0, :edges),
              self_loop_case[:graph][:edges].equal?(self_loop_case[:edges])]
    expect(actual).to eq([1, [self_loop_case[:routed_edge]], true])
  end

  it "matches routed sections by edge id and leaves an empty route untouched" do
    test_case = edge_section_case
    allow(Elkrb).to receive(:layout).and_return(test_case[:result])
    described_class.apply(test_case[:graph])
    actual = edge_section_result(test_case[:graph], test_case[:existing])
    expect(actual).to eq([test_case[:expected], true])
  end
end
