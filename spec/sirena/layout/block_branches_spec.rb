# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Block do
  subject(:layout) { described_class.new }

  def block(id, label: id, type: "block", compound: false)
    Sirena::Diagram::BlockNode.new(
      id: id, label: label, block_type: type, is_compound: compound,
    )
  end

  def mixed_nodes
    diagram = Sirena::Diagram::Block.new(
      columns: 2,
      blocks: [block("plain", label: nil), block("arrow", type: "arrow"),
               block("gap", type: "space"),
               block("container", compound: true)],
    )
    layout.call(diagram).children.to_h { |node| [node.id, node] }
  end

  def connected_scene
    diagram = Sirena::Diagram::Block.new(
      blocks: [block("a"), block("b")],
      connections: [
        Sirena::Diagram::BlockConnection.new(
          from: "a", to: "b", connection_type: "arrow",
        ),
        Sirena::Diagram::BlockConnection.new(
          from: "a", to: "missing", connection_type: "line",
        ),
      ],
    )
    layout.call(diagram)
  end

  def mixed_evidence
    mixed_nodes.values.map do |node|
      [node.id, node.labels.map(&:text), node.width, node.height,
       node.compound, node.children.map(&:id)]
    end
  end

  def expected_mixed_evidence
    [
      ["plain", [], 100.0, 60.0, false, []],
      ["arrow", ["arrow"], 50.0, 30.0, false, []],
      ["container", ["container"], 100.0, 60.0, true, []],
    ]
  end

  it "returns the minimum canvas for an empty diagram" do
    scene = layout.call(Sirena::Diagram::Block.new)

    expect(scene).to have_attributes(
      width: 40.0, height: 40.0, view_box: "0 0 40 40",
      children: [], edges: []
    )
  end

  it "handles unlabeled, arrow, space, and childless compound blocks" do
    expect(mixed_evidence).to eq(expected_mixed_evidence)
  end

  it "keeps valid connections and ignores dangling ones" do
    expect(connected_scene.edges)
      .to contain_exactly(have_attributes(source: "a", target: "b"))
  end
end
