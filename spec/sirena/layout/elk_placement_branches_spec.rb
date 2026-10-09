# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::ElkPlacement do
  let(:placed_node) do
    Struct.new(:x, :y, :width, :height, :children, keyword_init: true)
  end
  let(:placed_root) { placed_node.new(children: nil) }
  let(:spacing_graph) do
    spacing_key = Sirena::Layout::Base::ElkOptions::NODE_NODE_SPACING
    { layoutOptions: { spacing_key => 18 } }
  end
  let(:spacing_options) { { spacing_node_node: 18 } }
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

  def stub_layout(graph, options, result)
    allow(Elkrb).to receive(:layout)
      .with(graph, options)
      .and_return(result)
  end

  it "uses default options for a graph without layout metadata or children" do
    graph = {}
    allow(Elkrb).to receive(:layout).with(graph, {}).and_return(placed_root)

    expect(described_class.apply(graph)).to equal(graph)
  end

  it "compacts missing spacing values before calling elkrb" do
    stub_layout(spacing_graph, spacing_options, placed_root)
    described_class.apply(spacing_graph)
    expect(Elkrb).to have_received(:layout)
      .with(spacing_graph, spacing_options)
  end

  it "accepts explicit downward layout and copies nested positions" do
    options = { spacing_node_node: 12, layer_spacing: 34 }
    stub_layout(nested_case[:graph], options, nested_case[:placed])
    described_class.apply(nested_case[:graph])
    expect(nested_case[:nodes]).to eq(nested_case[:expected])
  end
end
