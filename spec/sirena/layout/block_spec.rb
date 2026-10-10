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

  describe "#call" do
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
        .to eq([%w[B C], [60.0]])
    end

    context "with a block whose span never fits the column count" do
      # spec/mermaid/block/002_rendering_block_spec_block_1.mmd: columns 2,
      # and every block after "fit" is wider than 2 columns, so each one
      # skips a row before it lands (see the comment in calculate_y_position).
      let(:source) do
        path = "../../mermaid/block/002_rendering_block_spec_block_1.mmd"
        File.read(File.expand_path(path, __dir__))
      end

      it "treats a skipped row as contributing zero height rather than nil" do
        diagram = parser.parse(source)
        blocks = transform.call(diagram).children.to_h do |node|
          [node.id, node]
        end
        ordered = blocks.values_at("fit", "overflow", "short", "also_overflow")
        expect(ordered.map(&:y))
          .to eq([20, 120, 200, 280])
      end
    end

    context "with a single column and widening spans" do
      # spec/mermaid/block/013: columns 1, and every block's span except A
      # exceeds it, so every row from B onward is skipped before landing.
      let(:source) do
        path = "../../mermaid/block/" \
               "013_parser_a_node_with_a_square_shape_and_a_label_12.mmd"
        File.read(File.expand_path(path, __dir__))
      end

      it "positions the last block without raising on the skipped rows" do
        diagram = parser.parse(source)
        scene = transform.call(diagram)
        blocks = scene.children.to_h { |node| [node.id, node] }

        expect(blocks["G"].y).to eq(600)
      end
    end
  end
end
