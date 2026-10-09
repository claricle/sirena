# frozen_string_literal: true

require "spec_helper"
require "sirena/diagram/mindmap"

RSpec.describe Sirena::Diagram::Mindmap do
  subject(:mindmap) { described_class.new }

  describe Sirena::Diagram::Mindmap::MindmapNode do
    subject(:root) { described_class.new(id: "root", content: "Root") }

    it "defaults to a root leaf with empty collections" do
      attributes = [root.level, root.shape, root.classes, root.children,
                    root.root?, root.leaf?]
      expect(attributes).to eq([0, "default", [], [], true, true])
    end

    it "attaches a child and derives its parent and level" do
      child = described_class.new(id: "child", content: "Child")

      root.add_child(child)

      attributes = [root.children, child.parent, child.level,
                    child.root?, child.leaf?, root.leaf?]
      expect(attributes).to eq([[child], root, 1, false, true, false])
    end
  end

  it "records every node and promotes only a level-zero node to root" do
    root = Sirena::Diagram::Mindmap::MindmapNode.new(id: "root")
    child = Sirena::Diagram::Mindmap::MindmapNode.new(id: "child", level: 1)

    mindmap.add_node(root)
    mindmap.add_node(child)

    expect([mindmap.nodes, mindmap.root]).to eq([[root, child], root])
  end

  it "reports its type and remains valid while validation is deferred" do
    expect([mindmap.diagram_type, mindmap.valid?]).to eq([:mindmap, true])
  end
end
