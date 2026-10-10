# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/architecture"

RSpec.describe Sirena::Notation::Mermaid::IRAdapters::Architecture do
  subject(:ir) { described_class.call(diagram) }

  let(:diagram) do
    Sirena::Diagram::Architecture.new(
      id: "", groups: [group], services: [service],
      edges: [unresolved_edge]
    )
  end
  let(:group) do
    Sirena::Diagram::Architecture::Group.new(id: "", label: "Platform")
  end
  let(:service) do
    Sirena::Diagram::Architecture::Service.new(
      id: "", label: "API", group_id: "",
    )
  end
  let(:unresolved_edge) do
    Sirena::Diagram::Architecture::Edge.new(
      from_id: "", to_id: "missing", label: "ignored",
    )
  end

  it "assigns stable fallback identities and drops unresolved connections" do
    expect(adapter_evidence)
      .to eq([true, "item", [], %w[group_0 service_0]])
  end

  def adapter_evidence
    roles = %w[group service]
    entities = ir.nodes.select do |node|
      roles.include?(node.role)
    end
    [ir.valid?, ir.id, ir.edges, entities.map(&:id)]
  end
end
