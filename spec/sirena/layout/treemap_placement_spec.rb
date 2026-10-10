# frozen_string_literal: true

require "spec_helper"
require "sirena/layout/treemap_placement"

RSpec.describe Sirena::Layout::TreemapPlacement do
  def leaf(value)
    { value: value, children: [] }
  end

  def section(*leaves)
    { value: leaves.sum { |node| node[:value] }, children: leaves }
  end

  def placed
    root = section(section(leaf(25), leaf(15)), section(leaf(10), leaf(20)))
    described_class.call(root, 1000, 400)
  end

  def edges(node)
    node.values_at(:x0, :y0, :x1, :y1)
  end

  it "insets sections by the header and the inner padding" do
    expect(edges(placed[:children].first)).to eq([10, 35, 566, 390])
  end

  it "separates sibling sections by the inner padding" do
    expect(edges(placed[:children].last)).to eq([576, 35, 990, 390])
  end

  it "insets leaves below the section header" do
    expect(edges(placed[:children].first[:children].first))
      .to eq([20, 70, 351, 380])
  end
end
