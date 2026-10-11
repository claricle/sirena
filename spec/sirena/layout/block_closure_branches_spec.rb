# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Block do
  subject(:layout) { described_class.new }

  let(:diagram) do
    Sirena::Diagram::Block.new(
      blocks: [Sirena::Diagram::BlockNode.new(
        id: "a", label: "Hello", block_type: "block",
      )],
    )
  end

  let(:node_sizes) do
    [Sirena::Theme.new, Sirena::Theme::Registry.get(:default)].map do |theme|
      node = layout.call(diagram, theme: theme).children.first
      [node.width, node.height]
    end
  end

  it "sizes blocks from the default font when the theme has no typography" do
    bare_size, default_size = node_sizes

    expect(bare_size).to eq(default_size)
  end

  describe "#build_graph with a prepositioned document" do
    let(:document) do
      blocks = %w[a b].map do |id|
        Sirena::Diagram::BlockNode.new(id: id, label: id, block_type: "block")
      end
      Sirena::Notation::Mermaid::IRAdapters::Block
        .call(Sirena::Diagram::Block.new(blocks: blocks))
    end

    before do
      %w[b ghost].each_with_index do |target, index|
        document.connections << Sirena::IR::Edge.new(
          id: "edge#{index}", source_id: "a", target_id: target, role: "arrow",
        )
      end
    end

    it "drops a connection whose target block was never laid out" do
      pairs = layout.build_graph(document)[:connections]
        .map { |connection| connection.values_at(:from, :to) }

      expect(pairs).to eq([%w[a b]])
    end
  end
end
