# frozen_string_literal: true

require "spec_helper"
require "sirena/layout/sankey"

RSpec.describe Sirena::Layout::Sankey do
  let(:properties) { Sirena::IR::PropertySet.new(weight: 2) }
  let(:edge) do
    Sirena::IR::Edge.new(
      id: "flow", role: "flow", source_id: "missing-source",
      target_id: "missing-target", properties: properties
    )
  end
  let(:graph) do
    Sirena::IR::Graph.new(
      id: "sankey", role: "flow_graph", nodes: [], edges: [edge],
    )
  end

  it "bounds direct scene geometry when endpoint nodes are absent" do
    flow = described_class.new.send(:scene, graph).flows.fetch(0)
    expect(flow).to have_attributes(
      source_x: 60.0, source_y: 100.0, target_x: 210.0, target_y: 100.0,
    )
  end
end
