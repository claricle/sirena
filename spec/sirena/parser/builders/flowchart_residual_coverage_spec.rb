# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Builders::Flowchart do
  subject(:builder) { described_class.new }

  let(:context) { described_class::Context.new }
  let(:diagram) { Sirena::Diagram::Flowchart.new }
  let(:subgraph_statement) do
    {
      subgraph_keyword: "subgraph",
      subgraph_id: "box",
      subgraph_statements: { node_id: "A" },
    }
  end
  let(:edge_statement) do
    {
      node: { node_id: "A" },
      edges: [nil, { arrow: { token: "-->" } }],
    }
  end

  it "ignores non-statement tree entries" do
    result = builder.apply([{ direction: { dir_value: "TD" } }, nil])

    expect([result.direction, result.nodes, result.edges]).to eq(["TD", [], []])
  end

  it "normalizes scalar statement collections while assigning ids" do
    builder.assign_ids(subgraph_statement, context)

    expect(context.ids[subgraph_statement]).to eq("box")
  end

  it "normalizes scalar statements while processing a subgraph" do
    builder.process_subgraph(diagram, subgraph_statement, context)

    expect([diagram.subgraphs.first.node_ids, diagram.nodes.map(&:id)])
      .to eq([["A"], ["A"]])
  end

  it "ignores non-edge entries and edges without targets" do
    builder.process_node_edge_statement(diagram, edge_statement, nil, context)

    expect([diagram.nodes.map(&:id), diagram.edges]).to eq([["A"], []])
  end

  it "leaves the diagram unchanged for absent node data" do
    added = builder.add_or_update_node(diagram, nil)
    extracted = builder.extract_node_data(nil)

    expect([added, extracted, diagram.nodes]).to eq([nil, nil, []])
  end

  it "normalizes collected ids and labels absent from an explicit shape" do
    id = builder.plain_id(string: %w[a b])
    shape = builder.bracket_shape(open: "[", close: "]", label: nil)

    expect([id, shape]).to eq(["ab", ["rect", nil]])
  end
end
