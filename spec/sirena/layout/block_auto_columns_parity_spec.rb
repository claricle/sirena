# frozen_string_literal: true

require "digest"
require "spec_helper"

RSpec.describe Sirena::Layout::Block do
  let(:layout) { described_class.new }
  let(:parser) { Sirena::Parser::Block.new }

  context "when columns are omitted" do
    subject(:column_contract) do
      diagram = parser.parse("block-beta\n  a\n")
      document = Sirena::Notation::Mermaid::IRAdapters::Block.call(diagram)
      settings = document.items.find { |item| item.role == "layout_settings" }
      equivalent = layout.call(document).to_json == layout.call(diagram).to_json
      [Sirena::Diagram::Block.new.columns, diagram.columns,
       settings, document.valid?, equivalent]
    end

    it { is_expected.to eq([nil, nil, nil, true, true]) }
  end

  context "with two auto-layout leaves and an edge" do
    subject(:geometry) do
      scene = layout.call(parser.parse(source))
      nodes = scene.children.map do |node|
        values = [node.x, node.y, node.width, node.height]
        [node.id, *values.map { |value| value.round(3) }]
      end
      section = scene.edges.first.sections.first
      points = [section.start_point.x, section.start_point.y,
                section.end_point.x, section.end_point.y]
      [scene.width, scene.height, nodes, points]
    end

    let(:source) { "block-beta\n  a\n  b\n  a --- b\n" }
    # Same source as corpus block_spec-e104ba37, whose pinned reference box
    # is 16.921875 wide (see block_compact_text_width_parity_spec.rb).
    let(:expected_geometry) do
      [
        69.792, 55.0,
        [["a", 8.0, 8.0, 16.896, 27.0],
         ["b", 32.896, 8.0, 16.896, 27.0]],
        [24.896, 21.5, 32.896, 21.5]
      ]
    end

    it { expect(geometry).to eq(expected_geometry) }
  end

  context "with one auto-layout leaf" do
    subject(:geometry) do
      scene = layout.call(parser.parse("block-beta\n  a\n"))
      node = scene.children.first
      [scene.width, scene.height, node.x, node.y,
       node.width.round(3), node.height]
    end

    it { is_expected.to eq([44.896, 55.0, 8.0, 8.0, 16.896, 27.0]) }
  end

  context "with an empty auto layout" do
    subject(:empty_scene) { layout.call(parser.parse("block-beta\n")) }

    let(:empty_attributes) do
      {
        width: 40.0, height: 40.0, view_box: "0 0 40 40",
        children: [], edges: []
      }
    end

    it { expect(empty_scene).to have_attributes(empty_attributes) }
  end

  context "with mixed auto-layout slots and spans" do
    subject(:slot_evidence) do
      graph = layout.build_graph(Sirena::Diagram::Block.new(blocks: blocks))
      positions = graph[:blocks].values_at("wide", "next", "group").map do |box|
        box.values_at(:row, :col, :col_span)
      end
      [graph[:columns], positions]
    end

    let(:blocks) do
      [
        Sirena::Diagram::BlockNode.new(
          id: "wide", label: "wide", width: 2,
        ),
        Sirena::Diagram::BlockNode.new(
          id: "gap", block_type: "space", width: 3,
        ),
        Sirena::Diagram::BlockNode.new(
          id: "next", label: "Next", block_type: "arrow", width: 0,
        ),
        Sirena::Diagram::BlockNode.new(
          id: "group", is_compound: true, width: 2,
          children: [Sirena::Diagram::BlockNode.new(id: "child", label: "C")]
        ),
      ]
    end

    it { is_expected.to eq([8, [[0, 0, 2], [0, 5, 1], [0, 6, 2]]]) }
  end

  context "with an explicit one-column grid" do
    subject(:explicit_evidence) do
      diagram = parser.parse(source)
      scene = layout.call(diagram)
      nodes = scene.children.map do |node|
        [node.x, node.y, node.width, node.height]
      end
      section = scene.edges.first.sections.first
      points = [section.start_point.x, section.start_point.y,
                section.end_point.x, section.end_point.y]
      document = Sirena::Notation::Mermaid::IRAdapters::Block.call(diagram)
      equivalent = layout.call(document).to_json == scene.to_json
      [Digest::SHA256.hexdigest(Sirena.render(source)), nodes, points,
       equivalent]
    end

    let(:source) do
      "block-beta\n  columns 1\n  a\n  b\n  a --- b\n"
    end
    let(:digest) do
      "bfd9aa15d9695f511098a7a17958da490fc1812216882eb6d4691ac4099771fc"
    end
    let(:expected_evidence) do
      [
        digest,
        [[20.0, 20.0, 100.0, 60.0], [20.0, 100.0, 100.0, 60.0]],
        [70.0, 80.0, 70.0, 100.0],
        true,
      ]
    end

    it { expect(explicit_evidence).to eq(expected_evidence) }
  end
end
