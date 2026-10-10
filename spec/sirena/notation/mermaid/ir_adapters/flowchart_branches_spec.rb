# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/flowchart"

RSpec.describe Sirena::Notation::Mermaid::IRAdapters::Flowchart do
  subject(:ir) { described_class.call(diagram) }

  let(:diagram) do
    Sirena::Diagram::Flowchart.new(
      nodes: [flow_node("first"), flow_node("second")],
      edges: [
        Sirena::Diagram::FlowchartEdge.new(
          source_id: "first", target_id: "second", arrow_type: "line",
        ),
      ],
    )
  end

  it "preserves a plain connection without inventing arrow markers" do
    edge = ir.edges.fetch(0)

    expect([edge.role, edge.properties.source_marker,
            edge.properties.target_marker])
      .to eq(["line", nil, nil])
  end

  def flow_node(id)
    Sirena::Diagram::FlowchartNode.new(id: id, label: id.capitalize)
  end
end
