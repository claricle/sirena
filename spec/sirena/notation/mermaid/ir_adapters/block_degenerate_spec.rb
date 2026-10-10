# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/block"

RSpec.describe Sirena::Notation::Mermaid::IRAdapters::Block do
  let(:node) do
    Sirena::Diagram::BlockNode.new(id: "a", label: "A", shape: nil)
  end
  let(:link) do
    Sirena::Diagram::BlockConnection.new(
      from: "a", to: "missing", connection_type: "arrow",
    )
  end
  let(:ir) do
    described_class.call(
      Sirena::Diagram::Block.new(blocks: [node], connections: [link]),
    )
  end

  it "drops a connection whose target is not a block" do
    expect(ir.connections).to be_empty
  end

  it "records no shape placement for a block without a shape" do
    dimensions = ir.items.flat_map { |item| item.placements.map(&:dimension) }

    expect(dimensions).not_to include("shape")
  end
end
