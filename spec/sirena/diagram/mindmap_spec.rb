# frozen_string_literal: true

require "spec_helper"
require "sirena/diagram/mindmap"

RSpec.describe Sirena::Diagram::Mindmap do
  describe Sirena::Diagram::Mindmap::MindmapNode do
    subject(:root) { described_class.new(id: "root", content: "Root") }

    it "defaults to a root leaf with empty collections" do
      expect([root.level, root.shape, root.classes, root.children])
        .to eq([0, "default", [], []])
      expect([root.root?, root.leaf?]).to eq([true, true])
    end

    it "attaches a child and derives its parent and level" do
      child = described_class.new(id: "child", content: "Child")

      root.add_child(child)

      expect(root.children).to eq([child])
      expect(child.parent).to equal(root)
      expect([child.level, child.root?, child.leaf?]).to eq([1, false, true])
      expect(root.leaf?).to be(false)
    end
  end

  subject(:mindmap) { described_class.new }

  it "records every node and promotes only a level-zero node to root" do
    root = Sirena::Diagram::Mindmap::MindmapNode.new(id: "root")
    child = Sirena::Diagram::Mindmap::MindmapNode.new(id: "child", level: 1)

    mindmap.add_node(root)
    mindmap.add_node(child)

    expect(mindmap.nodes).to eq([root, child])
    expect(mindmap.root).to equal(root)
  end

  it "reports its diagram type and remains valid while validation is deferred" do
    expect([mindmap.diagram_type, mindmap.valid?]).to eq([:mindmap, true])
  end
end
