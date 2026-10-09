# frozen_string_literal: true

require "spec_helper"
require "sirena/diagram/treemap"

RSpec.describe Sirena::Diagram::Treemap do
  subject(:diagram) { described_class.new }

  it "starts empty and reports its model contract" do
    expect(
      [diagram.root_nodes, diagram.class_defs,
       diagram.diagram_type, diagram.valid?],
    ).to eq([[], {}, :treemap, true])
  end

  it "tracks hierarchy, styles, totals, and depth" do
    root = Sirena::Diagram::TreemapNode.new("Root")
    leaf = Sirena::Diagram::TreemapNode.new("Leaf", "2.5")
    root.add_child(leaf)
    diagram.add_root_node(root)
    diagram.add_class_def("important", "fill:red")

    expect(
      [diagram.total_value, diagram.class_defs,
       root.leaf?, root.branch?, root.depth,
       leaf.leaf?, leaf.branch?, leaf.depth],
    ).to eq([2.5, { "important" => "fill:red" },
             false, true, 0, true, false, 1])
  end
end
