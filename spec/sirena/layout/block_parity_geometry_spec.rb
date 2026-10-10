# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Block do
  subject(:compound) do
    source = File.read("spec/mermaid/block/004_example_block_3.mmd")
    diagram = Sirena::Parser::Block.new.parse(source)
    described_class.new.call(diagram).children.find(&:compound)
  end

  def gaps(children)
    children.each_cons(2).map do |left, right|
      right.x - (left.x + left.width)
    end
  end

  def actual_geometry
    children = compound.children
    [
      children.map(&:id), children.map(&:y).uniq, gaps(children),
      compound.width, compound.height
    ]
  end

  def expected_geometry
    children = compound.children
    [
      %w[A B C], [compound.y + 8], [8.0, 8.0],
      children.sum(&:width) + 32, children.map(&:height).max + 16
    ]
  end

  it "lays out compound leaves as a padded horizontal row" do
    expect(actual_geometry).to eq(expected_geometry)
  end
end
