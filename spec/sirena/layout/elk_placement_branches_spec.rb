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

  def stub_layout(graph, options, result)
    allow(Elkrb).to receive(:layout)
      .with(graph, options)
      .and_return(result)
  end

  def capture_layout(result)
    received = []
    allow(Elkrb).to receive(:layout) do |*arguments|
      received.replace(arguments)
      result
    end
    received
  end

  def edge_section_result(graph, existing)
    [graph[:edges].first, graph[:edges].last[:sections].equal?(existing)]
  end

  it "uses default options for a graph without layout metadata or children" do
    graph = {}
    result = placed_node.new(children: nil)
    allow(Elkrb).to receive(:layout).with(graph, {}).and_return(result)

    expect(described_class.apply(graph)).to equal(graph)
  end

  it "compacts missing spacing values before calling elkrb" do
    options = { spacing_node_node: 18 }
    stub_layout(spacing_graph, options, placed_node.new(children: nil))
    described_class.apply(spacing_graph)
    expect(Elkrb).to have_received(:layout)
      .with(spacing_graph, options)
  end

  it "accepts explicit downward layout and copies nested positions" do
    options = { spacing_node_node: 12, layer_spacing: 34 }
    stub_layout(nested_case[:graph], options, nested_case[:placed])
    described_class.apply(nested_case[:graph])
    expect(nested_case[:nodes]).to eq(nested_case[:expected])
  end

  it "removes only self-loops from elkrb input and retains original edges" do
    received = capture_layout(placed_node.new(children: nil))
    described_class.apply(self_loop_case[:graph])
    actual = [received.dig(0, :edges), received[1],
              self_loop_case[:graph][:edges].equal?(self_loop_case[:edges])]
    expect(actual).to eq([[self_loop_case[:routed_edge]], {}, true])
  end

  it "matches routed sections by edge id and leaves an empty route untouched" do
    test_case = edge_section_case
    allow(Elkrb).to receive(:layout).and_return(test_case[:result])
    described_class.apply(test_case[:graph])
    actual = edge_section_result(test_case[:graph], test_case[:existing])
    expect(actual).to eq([test_case[:expected], true])
  end
end
