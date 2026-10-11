# frozen_string_literal: true

RSpec.describe Sirena::Layout::Flowchart::ClusterReach do
  def cluster(position, size, child_position)
    { id: "B", x: 0.0, width: 100.0, y: position, height: size,
      metadata: { cluster: true },
      children: [{ id: "c", x: 10.0, y: child_position, width: 80.0,
                   height: 50.0 }] }
  end

  def plain(id, position)
    { id: id, x: 0.0, y: position, width: 80.0, height: 50.0 }
  end

  let(:reach) { described_class::REACH }

  it "stretches a subgraph down the page to the boxes with an edge into it" do
    box = cluster(100.0, 110.0, 30.0)
    above = plain("a", 0.0)
    below = plain("b", 300.0)
    edges = [[nil, "a", "B"], [nil, "b", "B"]]

    described_class.apply([above, box, below], edges, sideways: true)

    expect([box[:y], box[:y] + box[:height]])
      .to eq([25.0 - reach, 325.0 + reach])
  end

  it "keeps the contents where they were on the page" do
    box = cluster(100.0, 110.0, 30.0)

    described_class.apply([plain("a", 0.0), box], [[nil, "a", "B"]],
                          sideways: true)

    expect(box[:children].first[:y] + box[:y]).to eq(130.0)
  end

  it "reaches for an edge that leaves the subgraph as well" do
    box = cluster(100.0, 110.0, 30.0)

    described_class.apply([box, plain("z", 400.0)], [[nil, "B", "z"]],
                          sideways: true)

    expect(box[:y] + box[:height]).to eq(425.0 + reach)
  end

  it "measures across the page when ranks run downward" do
    box = cluster(0.0, 110.0, 30.0).merge(x: 100.0)
    left = plain("a", 0.0).merge(x: 0.0)

    described_class.apply([left, box], [[nil, "a", "B"]], sideways: false)

    expect(box[:x]).to eq(40.0 - reach)
  end

  it "leaves a subgraph alone when its neighbours are within reach" do
    box = cluster(100.0, 110.0, 30.0)
    beside = plain("a", 135.0)

    described_class.apply([beside, box], [[nil, "a", "B"]], sideways: true)

    expect([box[:y], box[:height]]).to eq([100.0, 110.0])
  end

  it "leaves a plain box alone" do
    one = plain("a", 0.0)
    two = plain("b", 500.0)

    described_class.apply([one, two], [[nil, "a", "b"]], sideways: true)

    expect([one[:y], two[:y]]).to eq([0.0, 500.0])
  end
end
