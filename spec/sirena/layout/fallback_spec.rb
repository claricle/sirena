# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Fallback do
  def apply(graph)
    described_class.apply(graph)
  end

  def node(id, width: 100, height: 50)
    { id: id, width: width, height: height }
  end

  def cluster(id, children, label: { text: "T", width: 10, height: 14 })
    { id: id, width: 0, height: 0, children: children,
      labels: [label], metadata: { cluster: true } }
  end

  describe "a plain graph" do
    it "lays three nodes across and wraps the fourth" do
      graph = apply({ children: %w[a b c d].map { |id| node(id) } })
      spots = graph[:children].map { |c| [c[:x], c[:y]] }

      expect(spots).to eq([[50, 50], [300, 50], [550, 50], [50, 250]])
    end

    it "keeps children a transform placed itself" do
      placed = node("a").merge(x: 7, y: 9)

      expect(apply({ children: [placed] })[:children].first)
        .to include(x: 7, y: 9)
    end
  end

  # c4, class and er diagrams nest children of their own. Packing those
  # like clusters resized them and moved fifteen diagrams that have no
  # subgraph in them at all.
  describe "a nested child that is not a cluster" do
    let(:graph) do
      { children: [{ id: "outer", width: 100, height: 50,
                     children: [node("inner")] }] }
    end

    it "keeps the size the transform gave it" do
      outer = apply(graph)[:children].first

      expect(outer).to include(width: 100, height: 50)
    end

    it "leaves its contents on the same grid as anything else" do
      inner = apply(graph)[:children].first[:children].first

      expect([inner[:x], inner[:y]]).to eq([50, 50])
    end

    it "does not widen the column it sits in" do
      wide = { id: "outer", width: 900, height: 800, children: [node("in")] }
      graph = { children: [wide, node("b")] }

      expect(apply(graph)[:children].last[:x]).to eq(300)
    end
  end

  describe "a cluster" do
    it "takes a size big enough for its contents" do
      box = apply({ children: [cluster("s", [node("a")])] })[:children].first

      expect(box[:width]).to be > 100
      expect(box[:height]).to be > 50
    end

    # The exact spot, not just "clear of the box". `>=` is satisfied by a
    # gap of nothing, so it passed with CELL_GAP set to zero and the two
    # drawn edge to edge.
    it "widens the column it sits in, with a gap" do
      wide = cluster("s", [node("a", width: 400)])
      graph = { children: [wide, node("b")] }
      placed = apply(graph)[:children]
      box = placed.first

      # Literal numbers. Written in terms of the constants, the expected
      # value moves with them and the gap goes untested all over again.
      expect(box[:width]).to eq(440)
      expect(placed.last[:x]).to eq(520)
    end

    # The vertical twin of the column example above, and the same reason
    # for literal numbers: with `row_height` reduced to the floor the box
    # keeps its height and the next row starts underneath it anyway, so
    # only an exact y reports the overlap.
    it "makes the row it sits in taller, with a gap" do
      tall = cluster("s", [node("a", height: 400)])
      graph = { children: [tall, node("b"), node("c"), node("d")] }
      placed = apply(graph)[:children]

      expect(placed.first[:height]).to eq(474)
      expect(placed.last[:y]).to eq(554)
    end

    # The exact coordinates, because "smaller than the box" is also true
    # of the page coordinates a typical cluster would have had. On the
    # padding, and under a title band of the label height plus a padding
    # above and below it.
    it "positions its contents inside itself, not on the page" do
      padding = described_class::CLUSTER_PADDING
      box = apply({ children: [cluster("s", [node("a")])] })[:children].first
      inner = box[:children].first

      expect([inner[:x], inner[:y]]).to eq([padding, 14 + (padding * 2)])
    end

    it "drops its contents below the title" do
      label = { text: "T", width: 10, height: 14 }
      graph = apply({ children: [cluster("s", [node("a")], label: label)] })
      box = graph[:children].first

      expect(box[:children].first[:y]).to be > label[:height]
    end

    # From the TITLE, which is what the name claims. `> 0` is true of a
    # one-by-one box, so it never checked the title played any part.
    it "sizes a box with nothing in it from its title" do
      label = { text: "T", width: 10, height: 14 }
      box = apply({ children: [cluster("s", [], label: label)] })[:children].first
      padding = described_class::CLUSTER_PADDING

      expect(box[:width]).to eq(label[:width] + (padding * 2))
      expect(box[:height]).to eq(label[:height] + (padding * 3))
    end
  end
end
