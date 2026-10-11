# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::ClassCellPlacement do
  def box(id, width, height, **extra)
    { id: id, width: width, height: height, **extra }
  end

  def placed(children)
    described_class.apply({ children: children })
    children.map { |child| [child[:id], child[:x], child[:y]] }
  end

  it "starts the next column one gap past the widest box of the previous" do
    expect(placed([box("A", 300, 80), box("B", 100, 80)]))
      .to eq([["A", 50, 50], ["B", 400.0, 50]])
  end

  it "puts four unrelated classes in one dagre rank, 50 apart" do
    children = [box("A", 100, 80), box("B", 100, 300),
                box("C", 100, 80), box("D", 100, 80)]
    expect(placed(children).last).to eq(["D", 458.0, 8.0])
  end

  it "leaves a diagram with a namespace on Grid's cells" do
    children = [box("namespace:N", 400, 400, children: []),
                box("A", 100, 80)]
    expect(placed(children).last).to eq(["A", 300, 50])
  end

  it "keeps a position the caller already chose" do
    expect(placed([box("A", 100, 80, x: 7, y: 9)])).to eq([["A", 7, 9]])
  end
end
