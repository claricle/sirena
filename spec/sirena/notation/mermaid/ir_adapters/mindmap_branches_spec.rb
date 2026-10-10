# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/mindmap"

RSpec.describe Sirena::Notation::Mermaid::IRAdapters::Mindmap do
  def node(id, content)
    Sirena::Diagram::Mindmap::MindmapNode.new(id: id, content: content)
  end

  def colliding_mindmap
    root = node("mindmap", "Root")
    root.add_child(node("child", "Child"))
    root.add_child(node("mindmap_to_child", "Reserved edge id"))
    Sirena::Diagram::Mindmap.new(root: root)
  end

  it "maps an absent root to an empty graph" do
    ir = described_class.call(Sirena::Diagram::Mindmap.new)

    expect([ir.valid?, ir.id, ir.nodes, ir.edges])
      .to eq([true, "mindmap", [], []])
  end

  it "allocates graph and edge identities around node collisions" do
    ir = described_class.call(colliding_mindmap)
    expected_edges = %w[mindmap_to_child_2 mindmap_to_mindmap_to_child]

    expect([ir.valid?, ir.id, ir.edges.map(&:id)])
      .to eq([true, "mindmap_2", expected_edges])
  end
end
