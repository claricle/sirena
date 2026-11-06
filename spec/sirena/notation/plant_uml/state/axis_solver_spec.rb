# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml/state/axis_solver"

RSpec.describe Sirena::Notation::PlantUML::State::AxisSolver do
  let(:solver_class) { described_class }

  def item(rank, at, **options)
    solver_class::Item.new(rank: rank, width: 20.0, x: at, fixed: false,
                           **options)
  end

  def link(from, to, weight: 1, from_offset: 0.0, to_offset: 0.0)
    solver_class::Link.new(from: from, to: to, weight: weight,
                           from_offset: from_offset, to_offset: to_offset)
  end

  def solve(items, links, **options)
    solver_class.new(items, links, gap: 10.0, floor: 0.0, **options).solve
  end

  it "pulls an item under a fixed one" do
    anchor = item(0, 200.0, fixed: true)
    free = item(1, 20.0)
    solve([anchor, free], [link(anchor, free)])
    expect(free.x).to eq(200.0)
  end

  it "joins an item at its offset" do
    anchor = item(0, 200.0, fixed: true)
    free = item(1, 20.0)
    solve([anchor, free], [link(anchor, free, to_offset: 15.0)])
    expect(free.x).to eq(185.0)
  end

  it "keeps the items of a rank a width and a gap apart" do
    anchor = item(0, 100.0, fixed: true)
    pair = [item(1, 90.0), item(1, 110.0)]
    solve([anchor, *pair], pair.map { |each| link(anchor, each) })
    expect(pair.last.x - pair.first.x).to eq(30.0)
  end

  it "never moves a fixed item" do
    first = item(0, 100.0, fixed: true)
    second = item(0, 105.0, fixed: true)
    free = item(1, 0.0)
    solve([first, second, free], [link(first, free), link(second, free)])
    expect([first.x, second.x]).to eq([100.0, 105.0])
  end

  it "keeps an item right of the floor" do
    anchor = item(0, -50.0, fixed: true)
    free = item(1, 40.0)
    solve([anchor, free], [link(anchor, free)])
    expect(free.x).to eq(10.0)
  end

  it "keeps an item within its bounds" do
    anchor = item(0, 500.0, fixed: true)
    free = item(1, 40.0, low: 30.0, high: 120.0)
    solve([anchor, free], [link(anchor, free)])
    expect(free.x).to eq(120.0)
  end

  it "keeps an item whose high bound is below its low one at the low" do
    anchor = item(0, 500.0, fixed: true)
    free = item(1, 40.0, low: 60.0, high: 20.0)
    solve([anchor, free], [link(anchor, free)])
    expect(free.x).to eq(60.0)
  end

  it "ignores an item of another track on its rank" do
    anchor = item(0, 100.0, fixed: true)
    free = item(1, 0.0, track: :entry)
    other = item(1, 100.0, fixed: true)
    solve([anchor, free, other], [link(anchor, free)])
    expect(free.x).to eq(100.0)
  end

  it "moves the nodes of a long transition together" do
    nodes = [item(0, 100.0, fixed: true), item(1, 0.0), item(2, 0.0),
             item(3, 100.0, fixed: true)]
    chain = nodes.each_cons(2).map { |one, two| link(one, two, weight: 8) }
    solve(nodes, chain, chain_weight: 8)
    expect(nodes[1, 2].map(&:x)).to eq([100.0, 100.0])
  end

  it "leaves an unlinked item where it stands" do
    alone = item(0, 70.0)
    solve([alone], [])
    expect(alone.x).to eq(70.0)
  end

  it "compares items by identity" do
    expect(item(0, 1.0)).not_to eq(item(0, 1.0))
  end

  it "hashes an item the same after it moves" do
    one = item(0, 1.0)
    before = one.hash
    one.x = 5.0
    expect(one.hash).to eq(before)
  end
end
