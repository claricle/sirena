# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/flowchart"

RSpec.describe Sirena::Notation::Mermaid::IRAdapters::Flowchart do
  it "falls back to a generic id for an empty diagram id" do
    node = Sirena::Diagram::FlowchartNode.new(id: "a", label: "A")
    diagram = Sirena::Diagram::Flowchart.new(id: "", nodes: [node])

    expect(described_class.call(diagram).id).to eq("item")
  end
end
