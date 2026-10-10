# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/architecture"

RSpec.describe Sirena::Notation::Mermaid::IRAdapters::Architecture do
  let(:namespace) { Sirena::Diagram::Architecture }
  let(:diagram) do
    namespace.new(
      id: "", groups: [namespace::Group.new(id: "")],
      services: [namespace::Service.new(id: "")],
      junctions: [namespace::Junction.new(id: "")],
      edges: [namespace::Edge.new(from_id: "missing", to_id: "other")]
    )
  end
  let(:ir) { described_class.call(diagram) }

  it "falls back to a generic id for an empty diagram id" do
    expect(ir.id).to eq("item")
  end

  it "numbers entities that arrive without an id" do
    ids = ir.nodes.map(&:id) & %w[group_0 service_0 junction_0]

    expect(ids).to eq(%w[group_0 service_0 junction_0])
  end

  it "drops a connection whose endpoints are not entities" do
    expect(ir.edges).to be_empty
  end
end
