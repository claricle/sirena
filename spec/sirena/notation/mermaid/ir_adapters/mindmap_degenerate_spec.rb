# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/mindmap"

RSpec.describe Sirena::Notation::Mermaid::IRAdapters::Mindmap do
  it "suffixes the graph id when a node already uses it" do
    node = Sirena::Diagram::Mindmap::MindmapNode
    root = node.new(id: "mindmap", content: "r")
    diagram = Sirena::Diagram::Mindmap.new(root: root)

    expect(described_class.call(diagram).id).to eq("mindmap_2")
  end
end
