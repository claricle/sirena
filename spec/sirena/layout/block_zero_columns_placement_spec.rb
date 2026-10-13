# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Block do
  let(:source) do
    <<~MERMAID
      block-beta
        columns 0
        A["First"]
        B["Second"]
    MERMAID
  end
  let(:model) { Sirena::Parser::Block.new.parse(source) }
  let(:scene) { described_class.new.call(document) }
  let(:signature) do
    nodes = scene.children.map do |node|
      [node.id, node.x, node.y, node.width, node.height]
    end
    [scene.width, scene.height, scene.view_box, nodes]
  end

  {
    "the parsed model" => false,
    "shared prepositioned IR" => true,
  }.each do |name, shared|
    context "with #{name}" do
      let(:document) do
        if shared
          Sirena::Notation::Mermaid::IRAdapters::Block.call(model)
        else
          model
        end
      end

      it "preserves skipped rows and bounds for zero declared columns" do
        expect(signature).to eq(
          [140.0, 220.0, "0 0 140 220",
           [["A", 20.0, 40.0, 100.0, 60.0],
            ["B", 20.0, 140.0, 100.0, 60.0]]],
        )
      end
    end
  end
end
