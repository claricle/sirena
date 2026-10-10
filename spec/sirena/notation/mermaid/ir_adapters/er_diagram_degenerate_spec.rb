# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/er_diagram"

RSpec.describe Sirena::Notation::Mermaid::IRAdapters::ErDiagram do
  let(:diagram) do
    Sirena::Diagram::ErDiagram.new(
      id: "", entities: [Sirena::Diagram::ErEntity.new(id: "")],
      relationships: [Sirena::Diagram::ErRelationship.new(
        from_id: "missing", to_id: "other",
      )]
    )
  end
  let(:ir) { described_class.call(diagram) }

  it "falls back to a generic id for an empty diagram id" do
    expect(ir.id).to eq("item")
  end

  it "numbers an entity that arrives without an id" do
    expect(ir.nodes.first.id).to eq("entity_0")
  end

  it "drops a relationship whose endpoints are not entities" do
    expect(ir.edges).to be_empty
  end
end
