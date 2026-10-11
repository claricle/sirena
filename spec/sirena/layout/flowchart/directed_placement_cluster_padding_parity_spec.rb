# frozen_string_literal: true

module FlowchartClusterPaddingGraphs
  OPTIONS = Sirena::Layout::Base::ElkOptions

  def graph(children, edges = [])
    {
      id: "g",
      children: children,
      edges: edges.map.with_index do |(from, to), index|
        { id: "e#{index}", sources: [from], targets: [to], labels: [] }
      end,
      layoutOptions: {
        OPTIONS::DIRECTION => "DOWN",
        OPTIONS::LAYER_SPACING => 50,
        OPTIONS::NODE_NODE_SPACING => 50,
      },
    }
  end

  def node(id)
    { id: id, width: 76.0, height: 54.0 }
  end

  def cluster(id, children)
    {
      id: id,
      width: 0,
      height: 0,
      children: children,
      labels: [{ text: id, width: 30.0, height: 24.0 }],
      metadata: { cluster: true },
    }
  end

  def placed_cluster(input, id, within: nil)
    placed = described_class.apply(input)[:children]
    placed = placed.find { |box| box[:id] == within }[:children] if within
    placed.find { |box| box[:id] == id }
  end

  def margins(box)
    inner = box.fetch(:children)
    axis_margins(box, inner, :x, :width) +
      axis_margins(box, inner, :y, :height)
  end

  def axis_margins(box, children, axis, size)
    near_edge = children.map { |child| child[axis] }.min
    far_edge = children.map { |child| child[axis] + child[size] }.max
    [near_edge, box[size] - far_edge]
  end
end

RSpec.describe Sirena::Layout::Flowchart::DirectedPlacement do
  include FlowchartClusterPaddingGraphs

  it "keeps 37.5 points around a top-level independent leaf cluster" do
    leaf = cluster("leaf", [node("a"), node("b")])

    expect(margins(placed_cluster(graph([leaf]), "leaf")))
      .to eq([37.5, 37.5, 37.5, 37.5])
  end

  it "uses wide sides and compact vertical padding for a shallow cluster" do
    shallow = cluster("outer", [cluster("inner", [node("a")])])

    expect(margins(placed_cluster(graph([shallow]), "outer")))
      .to eq([37.5, 37.5, 25.0, 25.0])
  end

  it "keeps complex independent nesting compact" do
    complex = cluster("outer", [cluster("inner", [node("a"), node("b")])])

    expect(margins(placed_cluster(graph([complex]), "outer")))
      .to eq([8.0, 8.0, 25.0, 25.0])
  end

  it "uses 35-point sides when an edge crosses a top-level cluster" do
    crossed = cluster("held", [node("a")])

    expect(margins(placed_cluster(graph([crossed, node("x")], [%w[a x]]),
                                  "held")))
      .to eq([35.0, 35.0, 25.0, 25.0])
  end

  it "uses 37.5-point sides when an edge crosses a nested cluster" do
    nested = cluster("inner", [node("a")])
    outer = cluster("outer", [nested])

    expect(margins(placed_cluster(graph([outer, node("x")], [%w[a x]]),
                                  "inner", within: "outer")))
      .to eq([37.5, 37.5, 25.0, 25.0])
  end
end
