# frozen_string_literal: true

require "spec_helper"
require "sirena/diagram/treemap"

RSpec.describe Sirena::Diagram::Treemap do
  subject(:diagram) { described_class.new }

  let(:root) { Sirena::Diagram::TreemapNode.new("Root") }
  let(:leaf) { Sirena::Diagram::TreemapNode.new("Leaf", "2.5") }

  it "starts empty and reports its model contract" do
    expect(
      [diagram.root_nodes, diagram.class_defs,
       diagram.diagram_type, diagram.valid?],
    ).to eq([[], {}, :treemap, true])
  end

  context "with a styled hierarchy" do
    before do
      root.add_child(leaf)
      diagram.add_root_node(root)
      diagram.add_class_def("important", "fill:red")
    end

    it "tracks hierarchy, styles, totals, and depth" do
      values = [diagram.total_value, diagram.class_defs, root.leaf?,
                root.branch?, root.depth, leaf.leaf?, leaf.branch?, leaf.depth]
      expect(values).to eq([2.5, { "important" => "fill:red" },
                            false, true, 0, true, false, 1])
    end
  end
end
