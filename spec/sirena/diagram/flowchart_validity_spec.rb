# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Diagram::Flowchart do
  let(:node) { Sirena::Diagram::FlowchartNode.new(id: "A", label: "a") }

  it "is invalid when a node has no label" do
    unlabelled = Sirena::Diagram::FlowchartNode.new(id: "A", label: nil)
    expect(described_class.new(nodes: [unlabelled])).not_to be_valid
  end

  it "is valid when the edge list is absent" do
    expect(described_class.new(nodes: [node], edges: nil)).to be_valid
  end

  it "is invalid when an edge names no source" do
    edge = Sirena::Diagram::FlowchartEdge.new(source_id: "", target_id: "A")
    expect(described_class.new(nodes: [node], edges: [edge])).not_to be_valid
  end
end
