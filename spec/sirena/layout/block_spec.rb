# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Block do
  let(:transform) { described_class.new }
  let(:parser) { Sirena::Parser::Block.new }
  let(:basic_scene) do
    source = File.read("examples/block/01-basic-blocks.mmd")
    transform.call(parser.parse(source))
  end
  let(:shaped_scene) do
    source = File.read("examples/block/02-block-shapes.mmd")
    transform.call(parser.parse(source))
  end

  def nested_scene
    transform.call(parser.parse(<<~MERMAID))
      block-beta
        block:outer
          A
          block:inner
            B
            C
          end
        end
    MERMAID
  end

  def skipped_row_positions(source)
    diagram = parser.parse(source)
    blocks = transform.call(diagram).children.to_h { |node| [node.id, node] }
    blocks.values_at("fit", "overflow", "short", "also_overflow").map(&:y)
  end

  describe "#call" do
    it "lays out shared pre-positioned IR identically to the private model" do
      diagram = parser.parse(ir_equivalence_source)
      ir = Sirena::Notation::Mermaid::IRAdapters::Block.call(diagram)

      expect(scene_signature(transform.call(ir)))
        .to eq(scene_signature(transform.call(diagram)))
    end

    it "filters space nodes from typed final geometry" do
      expect(basic_scene.children.map(&:id))
        .to eq(%w[Frontend Backend Database Cache Queue])
    end

    it "keeps compound children as typed final geometry" do
      compound = shaped_scene.children.find { |node| node.id == "compound" }
      expect(compound.children)
        .to contain_exactly(have_attributes(id: "D"), have_attributes(id: "E"))
    end

    it "positions recursively nested compound children" do
      children = nested_scene.children.first.children
      inner = children.find { |node| node.id == "inner" }
      expect([inner.children.map(&:id), inner.children.map(&:x).uniq])
        .to eq([%w[B C], [132.0, 240.0]])
    end

    context "with a block whose final span exceeds the column count" do
      # spec/mermaid/block/block_spec-e162d2fc.mmd: columns 2,
      # and the final two-column block remains beside the preceding block.
      let(:source) do
        path = "../../mermaid/block/block_spec-e162d2fc.mmd"
        File.read(File.expand_path(path, __dir__))
      end

      it "keeps the overflowing final span in the current row" do
        expect(skipped_row_positions(source)).to eq([8.0, 43.0, 78.0, 78.0])
      end
    end

    context "with a single column and widening spans" do
      # spec/mermaid/block/a_node_with_a_square_shape_and_a_label-807b8b5c:
      # columns 1, with spans widening symmetrically from A through D.
      let(:source) do
        path = "../../mermaid/block/" \
               "a_node_with_a_square_shape_and_a_label-807b8b5c.mmd"
        File.read(File.expand_path(path, __dir__))
      end

      it "positions the last block on the compact seventh row" do
        diagram = parser.parse(source)
        scene = transform.call(diagram)
        blocks = scene.children.to_h { |node| [node.id, node] }

        expect(blocks["G"].y).to eq(218.0)
      end
    end
  end

  def ir_equivalence_source
    <<~MERMAID
      block-beta
        columns 3
        block:outer
          A["Service"]
          blockArrowId<["Next"]>(down)
        end
        space
        B(("Database")):2
        A --> B
    MERMAID
  end

  def scene_signature(scene)
    [scene.width, scene.height, scene.view_box,
     scene.children.map { |node| node_signature(node) },
     scene.edges.map { |edge| edge_signature(edge) }]
  end

  def node_signature(node)
    [node.id, node.x, node.y, node.width, node.height, node.shape,
     node.direction, node.compound, node.labels.map(&:text),
     node.children.map { |child| node_signature(child) }]
  end

  def edge_signature(edge)
    section = edge.sections.first
    [edge.source, edge.target, edge.connection_type,
     section.start_point.x, section.start_point.y,
     section.end_point.x, section.end_point.y]
  end
end
