# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Transform::BlockTransform do
  let(:transform) { described_class.new }
  let(:parser) { Sirena::Parser::BlockParser.new }

  describe "#to_graph" do
    context "with a block whose span never fits the column count" do
      # spec/mermaid/block/002_rendering_block_spec_block_1.mmd: columns 2,
      # and every block after "fit" is wider than 2 columns, so each one
      # skips a row before it lands (see the comment in calculate_y_position).
      let(:source) { File.read("spec/mermaid/block/002_rendering_block_spec_block_1.mmd") }

      it "positions every block without raising on the skipped rows" do
        diagram = parser.parse(source)

        expect { transform.to_graph(diagram) }.not_to raise_error
      end

      it "treats a skipped row as contributing zero height rather than nil" do
        diagram = parser.parse(source)
        blocks = transform.to_graph(diagram)[:blocks]

        expect(blocks["fit"][:y]).to eq(20)
        expect(blocks["overflow"][:y]).to eq(120)
        expect(blocks["short"][:y]).to eq(200)
        expect(blocks["also_overflow"][:y]).to eq(280)
      end
    end

    context "with a single column and widening spans" do
      # spec/mermaid/block/013: columns 1, and every block's span except A
      # exceeds it, so every row from B onward is skipped before landing.
      let(:source) { File.read("spec/mermaid/block/013_parser_a_node_with_a_square_shape_and_a_label_12.mmd") }

      it "positions the last block without raising on the skipped rows" do
        diagram = parser.parse(source)
        blocks = transform.to_graph(diagram)[:blocks]

        expect(blocks["G"][:y]).to eq(600)
      end
    end
  end
end
