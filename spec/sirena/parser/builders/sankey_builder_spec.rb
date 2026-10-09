# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Builders::Sankey do
  subject(:diagram) { described_class.new.apply(tree) }

  context "with a hash tree and statements" do
    let(:tree) do
      {
        node_declaration: { node_id: "a", node_label: "Alpha" },
        statements: [
          "noise",
          { node_declaration: { node_id: "a", node_label: "Renamed" } },
          { node_declaration: { node_id: "b", node_label: "" } },
          { node_declaration: { node_id: "b", node_label: "" } },
          { node_declaration: nil },
          { flow_entry: { source: "a", target: "c", value: { v: "2.5" } } },
          { flow_entry: nil },
        ],
      }
    end

    it "updates labels only when non-empty and keeps declared nodes" do
      expect(diagram.nodes.map do |n|
        [n.id, n.label]
      end).to eq([["a", "Renamed"], ["b", ""], ["c", "c"]])
    end

    it "records flows with float values and auto-creates undeclared targets" do
      expect(diagram.flows.map do |f|
        [f.source, f.target, f.value]
      end).to eq([["a", "c", 2.5]])
    end
  end

  context "with a lone hash and no statements" do
    let(:tree) { { flow_entry: { source: "s", target: "t", value: 1 } } }

    it "still discovers nodes from flows" do
      expect(diagram.nodes.map(&:id)).to eq(%w[s t])
    end
  end

  context "with non-hash entries in an array" do
    let(:tree) { ["noise", { header: "sankey-beta" }] }

    it "ignores them" do
      expect(diagram.nodes).to be_empty
    end
  end
end
