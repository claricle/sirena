# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/mindmap"

RSpec.describe Sirena::Notation::Mermaid::IRAdapters::Mindmap do
  let(:node_class) { Sirena::Diagram::Mindmap::MindmapNode }
  let(:root) do
    node_class.new(id: "mindmap", content: "r").tap do |node|
      node.children = [node_class.new(id: "mindmap_2", content: "c")]
    end
  end
  let(:diagram) { Sirena::Diagram::Mindmap.new(root: root) }

  it "suffixes the graph id past every id a node already uses" do
    expect(described_class.call(diagram).id).to eq("mindmap_3")
  end
end
