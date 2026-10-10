# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/requirement"

RSpec.describe Sirena::Notation::Mermaid::IRAdapters::Requirement do
  subject(:ir) { described_class.call(diagram) }

  let(:diagram) do
    Sirena::Diagram::Requirement.new(
      id: "", requirements: [requirement],
      relationships: [unresolved_relationship]
    )
  end
  let(:requirement) do
    Sirena::Diagram::RequirementNode.new(name: "", type: "custom")
  end
  let(:unresolved_relationship) do
    Sirena::Diagram::RequirementRelationship.new(
      source: "", target: "missing", type: "traces",
    )
  end

  it "uses collision-safe blank identities and omits absent semantics" do
    entity = ir.nodes.find { |node| node.role == "requirement" }
    children = ir.nodes.select { |node| node.parent_id == entity.id }

    expect([ir.valid?, ir.id, entity.id, children.map(&:role), ir.edges])
      .to eq([true, "item_2", "item", ["requirement_type"], []])
  end
end
