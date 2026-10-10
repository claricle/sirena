# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::C4 do
  subject(:layout) { described_class.new }

  def node(id = "node")
    described_class::Node.new(
      id: id, x: 0, y: 0, width: 40, height: 40, kind: "system",
    )
  end

  def missing_label_sets
    unpositioned = layout.send(
      :typed_node,
      { id: "plain", width: 40, height: 40, labels: [{ text: "Plain" }] },
    )
    boundary = layout.send(:typed_node, empty_boundary)
    [unpositioned.labels, boundary.labels]
  end

  def empty_boundary
    {
      id: "scope", x: 0, y: 0, width: 100, height: 80, labels: [],
      metadata: { boundary_type: "System_Boundary" }
    }
  end

  it "keeps a missing semantic element type missing" do
    element_class = described_class.const_get(:SemanticElement, false)

    expect(element_class.new(element_type: nil).base_type).to be_nil
  end

  it "builds graph defaults without a diagram settings node" do
    graph = Sirena::IR::Graph.new(id: "source", role: "architecture_graph")

    expect(layout.build_graph(graph))
      .to include(id: "c4", children: [], edges: [])
  end

  it "omits labels without positions and on an empty boundary" do
    expect(missing_label_sets).to eq([[], []])
  end

  it "filters an edge whose endpoint collections are absent" do
    edges = layout.send(:typed_edges, [{ id: "missing-endpoints" }], [node])

    expect(edges).to be_empty
  end

  it "uses minimum dimensions for an empty boundary" do
    expect(layout.send(:calculate_boundary_dimensions, []))
      .to eq(width: 300, height: 200)
  end
end
