# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/flowchart"

module FlowchartIRAdapterSpecHelpers
  ENTITY_ROLES = %w[flow_node group].freeze

  def flowchart_node(id, label, shape, classes = nil)
    Sirena::Diagram::FlowchartNode.new(
      id: id, label: label, shape: shape, classes: classes,
    )
  end

  def flowchart_edge(source, target, arrow, label = nil)
    Sirena::Diagram::FlowchartEdge.new(
      source_id: source, target_id: target,
      arrow_type: arrow, label: label
    )
  end

  def flowchart_group(id, title, **attributes)
    Sirena::Diagram::FlowchartSubgraph.new(
      id: id, declared_title: title, parent_id: attributes[:parent],
      node_ids: attributes.fetch(:nodes, []),
      child_ids: attributes.fetch(:children, []),
      direction: attributes[:direction]
    )
  end

  def semantics(graph, node)
    graph.nodes.select { |candidate| candidate.parent_id == node.id }
      .reject { |candidate| ENTITY_ROLES.include?(candidate.role) }
      .group_by(&:role).transform_values { |values| values.map(&:label) }
  end

  def expected_node_details
    [
      { "source_identifier" => ["flowchart"], "shape" => ["stadium"],
        "style_reference" => [":::hot"] },
      { "source_identifier" => ["task"], "shape" => ["rhombus"],
        "style_reference" => [":::cold"] },
      { "source_identifier" => ["flowchart_to_task"], "shape" => ["rect"] },
    ]
  end

  def expected_containment(groups)
    [
      [groups[0].id, groups[1].id, groups[1].id],
      [nil, groups[0].id],
      [
        { "source_identifier" => ["outer"] },
        { "source_identifier" => ["inner"],
          "layout_direction" => ["BT"] },
      ],
    ]
  end

  def edge_evidence(graph, flow_nodes)
    labels = flow_nodes.to_h { |node| [node.id, node.label] }
    graph.edges.map { |edge| edge_signature(edge, labels) }
  end

  def edge_signature(edge, labels)
    markers = edge.properties
    [labels.fetch(edge.source_id), labels.fetch(edge.target_id),
     edge.label, edge.role, markers.source_marker, markers.target_marker]
  end

  def expected_edges
    [
      ["Start", "Choose", "yes", "thick_arrow_both", "arrow", "arrow"],
      ["Choose", "Finish", "no", "dotted_cross", nil, "cross"],
    ]
  end

  def accessible_graph(adapter)
    klass = Class.new(Sirena::Diagram::Flowchart) do
      attribute :acc_title, :string
      attribute :acc_description, :string
      attribute :acc_descr, :string
    end
    private_model = klass.new(
      nodes: [], acc_title: "Process", acc_descr: "Steps",
    )
    adapter.call(private_model)
  end

  def duplicate_group_graph
    first = flowchart_group("section", "First", nodes: ["one"])
    second = flowchart_group("section", "Second", nodes: ["two"])
    source = Sirena::Diagram::Flowchart.new(
      nodes: [flowchart_node("one", "One", "rect"),
              flowchart_node("two", "Two", "rect"),
              flowchart_node("target", "Target", "rect")],
      edges: [flowchart_edge("section", "target", "arrow")],
      subgraphs: [first, second],
    )
    described_class.call(source)
  end

  def diagram_evidence(graph)
    settings = graph.nodes.find { |node| node.role == "diagram_settings" }
    [graph.label, graph.role, semantics(graph, settings)]
  end

  def expected_diagram_evidence
    [
      "Pipeline", "flow_diagram",
      { "diagram_identifier" => ["flowchart"],
        "layout_direction" => ["LR"], "theme_reference" => ["dark"] }
    ]
  end
end

RSpec.describe Sirena::Notation::Mermaid::IRAdapters::Flowchart do
  include FlowchartIRAdapterSpecHelpers

  let(:diagram) do
    outer = flowchart_group(
      "outer", "Outer", nodes: ["flowchart"], children: ["inner"]
    )
    inner = flowchart_group(
      "inner", "Inner",
      parent: "outer", nodes: %w[task flowchart_to_task], direction: "BT"
    )
    Sirena::Diagram::Flowchart.new(
      id: "flowchart", title: "Pipeline", direction: "LR", theme: "dark",
      nodes: [
        flowchart_node("flowchart", "Start", "stadium", ":::hot"),
        flowchart_node("task", "Choose", "rhombus", ":::cold"),
        flowchart_node("flowchart_to_task", "Finish", "rect"),
      ],
      edges: [
        flowchart_edge("flowchart", "task", "thick_arrow_both", "yes"),
        flowchart_edge("task", "flowchart_to_task", "dotted_cross", "no"),
      ],
      subgraphs: [outer, inner]
    )
  end
  let(:graph) { described_class.call(diagram) }
  let(:flow_nodes) do
    graph.nodes.select { |node| node.role == "flow_node" }
  end
  let(:groups) { graph.nodes.select { |node| node.role == "group" } }

  it "builds a valid collision-safe graph in source order" do
    ids = [graph, *graph.items].map(&:id)

    expect([graph.valid?, ids.uniq.size, ids.size, flow_nodes.map(&:label)])
      .to eq([true, ids.size, ids.size, %w[Start Choose Finish]])
  end

  it "preserves shapes and styles" do
    actual = flow_nodes.map { |node| semantics(graph, node) }

    expect(actual).to eq(expected_node_details)
  end

  it "preserves nesting and local layout intent" do
    details = groups.map { |group| semantics(graph, group) }
    actual = [flow_nodes.map(&:parent_id), groups.map(&:parent_id), details]

    expect(actual).to eq(expected_containment(groups))
  end

  it "preserves endpoint, arrow, label, and marker semantics" do
    expect(edge_evidence(graph, flow_nodes)).to eq(expected_edges)
  end

  it "resolves a repeated source endpoint to the first declared entity" do
    repeated = duplicate_group_graph
    boxes = repeated.nodes.select { |node| node.role == "group" }

    expect([boxes.map(&:id), repeated.edges.first.source_id])
      .to eq([%w[section section_2], boxes.first.id])
  end

  it "preserves diagram layout and presentation intent" do
    expect(diagram_evidence(graph)).to eq(expected_diagram_evidence)
  end

  it "carries accessibility fields when the private model exposes them" do
    result = accessible_graph(described_class)

    expect([result.accessibility_title, result.accessibility_description])
      .to eq(["Process", "Steps"])
  end

  it "puts no dimensions, measurements, coordinates, or routes in IR" do
    forbidden = %i[x y width height path points route bend_points]
    exposed = [graph, *graph.items].flat_map do |item|
      forbidden.select { |name| item.respond_to?(name) }
    end

    expect(exposed).to eq([])
  end

  it "does not mutate the private source model" do
    before = Marshal.dump(diagram)

    described_class.call(diagram)

    expect(Marshal.dump(diagram)).to eq(before)
  end
end
