# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Block, :aggregate_failures do
  subject(:scene) { described_class.new.call(parser.parse(source)) }

  let(:parser) { Sirena::Parser::Block.new }

  context "with the mixed one-column block-b7a88657 fixture" do
    let(:source) { fixture("block-b7a88657") }

    it "uses a compact uniform grid while preserving special shapes" do
      nodes = scene.children.to_h { |node| [node.id, node] }
      compound = nodes.fetch("ID")
      children = compound.children

      expect([
        nodes.fetch("db").shape,
        nodes.fetch("blockArrowId6").shape,
        nodes.fetch("blockArrowId6").labels.first.text,
        children.map(&:width).uniq,
        children.map(&:height).uniq,
        nodes.fetch("D").width,
        compound.width,
      ]).to match([
        "circle", "arrow", "\u00a0\u00a0\u00a0",
        [be_within(0.001).of(184.919)], [27.0],
        be_within(0.001).of(compound.width), compound.width,
      ])
    end
  end

  context "with the compound two-column block_spec-532fdf55 fixture" do
    let(:source) { fixture("block_spec-532fdf55") }

    it "shares compact cell dimensions between peers and compound children" do
      compound, following = scene.children
      left, right = compound.children

      expect([
        following.x - compound.x - compound.width,
        right.x - left.x - left.width,
        [compound.width, following.width].uniq,
        [compound.height, following.height].uniq,
        [left.width, right.width].uniq,
        [left.height, right.height].uniq,
      ]).to match([
        8.0, 8.0, [be_within(0.001).of(269.276)], [43.0],
        [be_within(0.001).of(122.638)], [27.0],
      ])
    end
  end

  context "with the automatic block_spec-e104ba37 fixture" do
    let(:source) { fixture("block_spec-e104ba37") }

    it "uses Mermaid's compact peer gap" do
      left, right = scene.children

      expect(right.x - left.x - left.width).to eq(8.0)
    end
  end

  def fixture(name)
    File.read("spec/mermaid/block/#{name}.mmd")
  end
end
