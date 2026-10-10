# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/block"

RSpec.describe Sirena::Notation::Mermaid::IRAdapters::Block do
  let(:diagram) do
    Sirena::Diagram::Block.new(
      id: "outer", title: "System blocks", columns: 3,
      blocks: [
        outer,
        Sirena::Diagram::BlockNode.new(id: "gap", block_type: "space"),
        Sirena::Diagram::BlockNode.new(id: "database", label: "DB"),
      ],
      connections: [Sirena::Diagram::BlockConnection.new(
        from: "service", to: "database", connection_type: "arrow",
        label: "writes"
      )]
    )
  end
  let(:outer) do
    Sirena::Diagram::BlockNode.new(
      id: "outer", label: "Services", is_compound: true,
      children: [
        service,
        Sirena::Diagram::BlockNode.new(
          id: "direction", label: "Next", block_type: "arrow",
          direction: "down"
        ),
      ]
    )
  end
  let(:service) do
    Sirena::Diagram::BlockNode.new(
      id: "service", label: "API", width: 2, shape: "rounded",
    )
  end
  let(:ir) { described_class.call(diagram) }

  it "produces valid collision-free pre-positioned IR" do
    expect([ir.valid?, ir.id, ir.items.map(&:id).uniq.length])
      .to eq([true, "outer_2", ir.items.length])
  end

  it "preserves columns, order, spans, shapes, nesting, and spaces" do
    expect(block_signature).to eq(expected_block_signature)
  end

  it "preserves resolved connection semantics" do
    edge = ir.connections.first
    expect([edge.label, edge.role, edge.source_id, edge.target_id])
      .to eq(["writes", "arrow", "service", "database"])
  end

  def block_signature
    ir.items.map do |item|
      [item.id, item.label, item.role, item.parent_id,
       item.placements.map { |placement| placement_signature(placement) }]
    end
  end

  def placement_signature(placement)
    [placement.dimension, placement.ordinal, placement.value.value]
  end

  def expected_block_signature
    [
      ["layout_settings", nil, "layout_settings", nil,
       [["column_count", 0, 3.0]]],
      ["outer", "Services", "block", nil,
       [["source_order", 0, 0.0], ["column_span", 1, 1.0],
        ["compound", 2, true], ["shape", 3, "rect"]]],
      ["service", "API", "block", "outer",
       [["source_order", 0, 1.0], ["column_span", 1, 2.0],
        ["compound", 2, false], ["shape", 3, "rounded"]]],
      ["direction", "Next", "arrow", "outer",
       [["source_order", 0, 2.0], ["column_span", 1, 1.0],
        ["compound", 2, false], ["shape", 3, "rect"],
        ["direction", 4, "down"]]],
      ["gap", nil, "space", nil,
       [["source_order", 0, 3.0], ["column_span", 1, 1.0],
        ["compound", 2, false], ["shape", 3, "rect"]]],
      ["database", "DB", "block", nil,
       [["source_order", 0, 4.0], ["column_span", 1, 1.0],
        ["compound", 2, false], ["shape", 3, "rect"]]],
    ]
  end
end
