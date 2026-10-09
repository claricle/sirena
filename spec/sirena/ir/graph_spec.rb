# frozen_string_literal: true

require "spec_helper"
require "sirena/ir"

RSpec.describe Sirena::IR::Graph do
  def edge(id, source_id, target_id, parent_id: nil)
    Sirena::IR::Edge.new(
      id: id, source_id: source_id, target_id: target_id,
      parent_id: parent_id
    )
  end

  context "with ordered nodes and a resolved edge" do
    subject(:ir) do
      nodes = [Sirena::IR::Node.new(id: "parent"),
               Sirena::IR::Node.new(id: "child", parent_id: "parent")]
      described_class.new(
        id: "graph", nodes: nodes, edges: [edge("link", "parent", "child")],
      )
    end

    it "preserves ordered nodes, containment, and resolved edges" do
      expect([ir.valid?, ir.nodes.map(&:id), ir.edges.map(&:id)])
        .to eq([true, %w[parent child], ["link"]])
    end
  end

  context "with invalid connectivity" do
    subject(:results) { [duplicate.valid?, dangling.valid?] }

    let(:duplicate) do
      described_class.new(
        id: "graph", nodes: [Sirena::IR::Node.new(id: "a")],
        edges: [edge("a", "a", "a")]
      )
    end
    let(:dangling) do
      described_class.new(
        id: "graph", nodes: [Sirena::IR::Node.new(id: "a")],
        edges: [edge("link", "a", "missing")]
      )
    end

    it "rejects duplicate identities and unknown endpoints" do
      expect(results).to eq([false, false])
    end
  end

  context "with invalid containment" do
    subject(:results) { [unresolved.valid?, cycle.valid?] }

    let(:unresolved) do
      described_class.new(
        id: "graph", nodes: [Sirena::IR::Node.new(
          id: "a", parent_id: "missing",
        )]
      )
    end
    let(:cycle) do
      described_class.new(
        id: "graph", nodes: [Sirena::IR::Node.new(id: "a", parent_id: "b"),
                             Sirena::IR::Node.new(id: "b", parent_id: "a")]
      )
    end

    it "rejects unresolved and cyclic parents" do
      expect(results).to eq([false, false])
    end
  end

  context "with valid boundary-case graphs" do
    subject(:results) { [empty.valid?, looped.valid?] }

    let(:empty) { described_class.new(id: "empty") }
    let(:looped) do
      described_class.new(
        id: "graph", nodes: [Sirena::IR::Node.new(id: "a")],
        edges: [edge("loop", "a", "a")]
      )
    end

    it "allows empty graphs and self-loops" do
      expect(results).to eq([true, true])
    end
  end
end
