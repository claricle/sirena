# frozen_string_literal: true

require "spec_helper"
require "sirena/layout/treemap_squarify"

RSpec.describe Sirena::Layout::TreemapSquarify do
  def tiled(values, bounds)
    nodes = values.map { |value| { value: value } }
    described_class.call(nodes, values.sum, bounds)
    nodes.map { |node| node.values_at(:x0, :y0, :x1, :y1) }
  end

  it "puts two siblings side by side on a wide area" do
    expect(tiled([30, 10], [0, 0, 400, 100]))
      .to eq([[0, 0, 300, 100], [300, 0, 400, 100]])
  end

  it "stacks two siblings on a tall area" do
    expect(tiled([30, 10], [0, 0, 100, 400]))
      .to eq([[0, 0, 100, 300], [0, 300, 100, 400]])
  end

  it "fills the left half with a column when columns are squarer" do
    expect(tiled([6, 6, 4, 3, 2, 2, 1], [0, 0, 600, 400]).first(2))
      .to eq([[0, 0, 300, 200], [0, 200, 300, 400]])
  end
end
