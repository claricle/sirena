# frozen_string_literal: true

require "spec_helper"
require "sirena/diagram/treemap"

RSpec.describe Sirena::Diagram::Treemap do
  describe Sirena::Diagram::TreemapNode do
    it "uses zero for an empty node" do
      node = described_class.new("Empty")

      expect([node.leaf?, node.branch?, node.total_value])
        .to eq([false, false, 0.0])
    end

    it "uses a leaf value even when the node also has children" do
      node = described_class.new("Budget", 10)
      node.add_child(described_class.new("Detail", 4))

      expect(node.total_value).to eq(10.0)
    end

    it "sums branch descendants and derives recursive depth" do
      root = described_class.new("Root")
      branch = described_class.new("Branch")
      branch.add_child(described_class.new("Leaf", 3))
      root.add_child(branch)
      expect([root.total_value, branch.children.first.depth]).to eq([3.0, 2])
    end
  end
end
