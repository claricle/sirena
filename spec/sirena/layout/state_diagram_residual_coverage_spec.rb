# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::StateDiagram do
  subject(:layout) { described_class.new }

  def state(id, x_position = 0)
    {
      id: id, x: x_position, y: 0, width: 60, height: 40,
      metadata: { state_type: "normal" }
    }
  end

  def default_metadata
    graph = Sirena::IR::Graph.new(id: "states", role: "state_machine")
    semantics = graph.nodes.group_by(&:parent_id)
    [layout.send(:diagram_identifier, graph, semantics),
     layout.send(:layout_direction, graph, semantics)]
  end

  def missing_transition_edge
    node = Sirena::IR::Node.new(id: "state-a", label: "A", role: "state")
    graph = Sirena::IR::Graph.new(
      id: "states", role: "state_machine", nodes: [node],
      edges: [annotation_edge(node), absent_source_edge(node)]
    )
    layout.send(:build_graph, graph).fetch(:edges).first
  end

  def annotation_edge(node)
    Sirena::IR::Edge.new(
      id: "note", role: "annotation_edge",
      source_id: node.id, target_id: node.id
    )
  end

  def absent_source_edge(node)
    Sirena::IR::Edge.new(
      id: "missing", role: "state_transition",
      source_id: "absent", target_id: node.id
    )
  end

  def fallback_sizes
    layout.theme = double(typography: nil)
    [layout.send(:normal_font_size), layout.send(:small_font_size)]
  end

  it "measures renderer extents from a typed scene" do
    scene = described_class::Scene.new(width: 640, height: 480)

    expect(described_class.renderer_extent(scene, :width)).to eq(600)
  end

  it "defaults graph metadata when no settings node exists" do
    expect(default_metadata).to eq(["state_diagram", nil])
  end

  it "uses the no-children canvas defaults" do
    scene = described_class.from_graph({})

    expect(scene).to have_attributes(width: 840, height: 640)
  end

  it "filters an edge whose endpoint collections are absent" do
    graph = {
      children: [state("A")], edges: [{ id: "missing-endpoints" }]
    }
    scene = described_class.from_graph(graph)

    expect(scene.edges).to be_empty
  end

  it "filters non-transitions and preserves an absent state endpoint" do
    expect(missing_transition_edge)
      .to include(sources: [nil], targets: ["state-a"])
  end

  it "falls back when theme typography is absent" do
    expect(fallback_sizes).to eq([14.0, 12.0])
  end
end
