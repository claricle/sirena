# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/sankey"

RSpec.describe Sirena::Notation::Mermaid::IRAdapters::Sankey do
  def colliding_sankey
    diagram = Sirena::Diagram::Sankey.new
    diagram.nodes = [
      Sirena::Diagram::SankeyNode.new("sankey"),
      Sirena::Diagram::SankeyNode.new("flow_0"),
    ]
    diagram.flows = [Sirena::Diagram::SankeyFlow.new("sankey", "flow_0", 2)]
    diagram
  end

  it "allocates graph and edge identities around node collisions" do
    ir = described_class.call(colliding_sankey)

    expect([ir.valid?, ir.id, ir.nodes.map(&:id), ir.edges.map(&:id)])
      .to eq([true, "sankey_2", %w[sankey flow_0], ["flow_0_2"]])
  end
end
