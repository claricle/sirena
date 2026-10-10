# frozen_string_literal: true

require "spec_helper"
require "sirena/ir"

RSpec.describe Sirena::Notation::Mermaid::IRAdapter do
  def sankey_node(id, label = nil)
    Sirena::Diagram::SankeyNode.new(id, label)
  end

  def sankey_flow(source, target, value)
    Sirena::Diagram::SankeyFlow.new(source, target, value)
  end

  let(:colliding_sankey) do
    Sirena::Diagram::Sankey.new.tap do |diagram|
      diagram.title = "Energy"
      diagram.acc_title = "Accessible energy"
      diagram.acc_description = "Energy movements"
      diagram.nodes = [sankey_node("sankey", "Source"), sankey_node("flow_0")]
      diagram.flows = [sankey_flow("sankey", "sankey", 2),
                       sankey_flow("sankey", "flow_0", 3)]
    end
  end
  let(:sankey_graph) { described_class.call(:sankey, colliding_sankey) }
  let(:sankey_comparison) do
    metadata = [sankey_graph.label, sankey_graph.accessibility_title,
                sankey_graph.accessibility_description]
    nodes = sankey_graph.nodes.map { |node| [node.id, node.label] }
    edges = sankey_graph.edges.map do |edge|
      [edge.source_id, edge.target_id, edge.properties.weight]
    end
    actual = [sankey_graph.valid?, metadata, nodes, edges]
    expected_nodes = [["sankey", "Source"], ["flow_0", "flow_0"]]
    expected_edges = [["sankey", "sankey", 2.0],
                      ["sankey", "flow_0", 3.0]]
    [actual, [true, ["Energy", "Accessible energy", "Energy movements"],
              expected_nodes, expected_edges]]
  end
  let(:mindmap_graph) do
    diagram = Sirena::Parser::Mindmap.new.parse(<<~MERMAID)
      mindmap
        root((Root))
          branch[Branch]
            leaf{{Leaf}}
    MERMAID
    described_class.call(:mindmap, diagram)
  end
  let(:mindmap_comparison) do
    nodes = mindmap_graph.nodes.map do |node|
      [node.id, node.parent_id, node.role]
    end
    edges = mindmap_graph.edges.map do |edge|
      [edge.source_id, edge.target_id]
    end
    actual = [mindmap_graph.valid?, nodes, edges]
    expected_nodes = [
      ["node-0", nil, "circle"],
      ["node-1", "node-0", "square"],
      ["node-2", "node-1", "hexagon"],
    ]
    expected_edges = [["node-0", "node-1"], ["node-1", "node-2"]]
    expected = [true, expected_nodes, expected_edges]
    [actual, expected]
  end

  it "maps Sankey identity, values, labels, and accessibility metadata" do
    expect(sankey_comparison.first).to eq(sankey_comparison.last)
  end

  it "materializes implicit Sankey endpoints as shared nodes" do
    diagram = Sirena::Diagram::Sankey.new
    diagram.flows = [sankey_flow("source", "target", 1)]
    graph = described_class.call(:sankey, diagram)

    expect([graph.valid?, graph.nodes.map(&:id)])
      .to eq([true, %w[source target]])
  end

  it "resolves every nested Mindmap parent and endpoint by identity" do
    expect(mindmap_comparison.first).to eq(mindmap_comparison.last)
  end

  it "leaves an unmigrated diagram unchanged" do
    diagram = Sirena::Parser::Flowchart.new.parse(
      File.read("spec/fixtures/contract/flowchart.mmd"),
    )

    expect(described_class.call(:flowchart, diagram)).to equal(diagram)
  end

  it "discovers opted-in adapters by the registered type name" do
    actual = [opted_in_types, described_class.const_defined?(:ADAPTERS, false)]
    expect(actual).to eq([expected_opted_in_types, false])
  end

  def opted_in_types
    %i[
      mindmap sankey pie info error packet timeline kanban radar treemap
      quadrant xychart block gantt requirement user_journey
    ].to_h do |type|
      source = File.read("spec/fixtures/contract/#{type}.mmd")
      [type, Sirena::Notation::Mermaid.parse(source).diagram.class]
    end
  end

  def expected_opted_in_types
    {
      mindmap: Sirena::IR::Graph, sankey: Sirena::IR::Graph,
      requirement: Sirena::IR::Graph,
      user_journey: Sirena::IR::Graph,
      pie: Sirena::IR::Data, info: Sirena::IR::Data, error: Sirena::IR::Data,
      kanban: Sirena::IR::Data, radar: Sirena::IR::Data,
      treemap: Sirena::IR::Data,
      packet: Sirena::IR::Prepositioned,
      timeline: Sirena::IR::Prepositioned,
      quadrant: Sirena::IR::Prepositioned,
      xychart: Sirena::IR::Prepositioned,
      block: Sirena::IR::Prepositioned,
      gantt: Sirena::IR::Prepositioned
    }
  end
end
