# frozen_string_literal: true

# Hand-built ELK graphs, so a spec sets the box sizes mmdc measured instead
# of leaning on text measurement.
module DirectedPlacementGraphs
  OPTIONS = Sirena::Layout::Base::ElkOptions

  def level_graph(direction, children, edges = [])
    { id: "g",
      layoutOptions: { OPTIONS::DIRECTION => direction,
                       OPTIONS::LAYER_SPACING => 50,
                       OPTIONS::NODE_NODE_SPACING => 50 },
      children: children,
      edges: edges.map.with_index do |(from, to), index|
        { id: "e#{index}", sources: [from], targets: [to], labels: [] }
      end }
  end

  def node(id, width = 76.796875)
    { id: id, width: width, height: 54.0 }
  end

  def subgraph(id, children, direction: nil)
    { id: id, width: 0, height: 0, children: children,
      labels: [{ text: id, width: 30.0, height: 24.0 }],
      metadata: { cluster: true, direction: direction }.compact }
  end

  def placed(graph)
    described_class.apply(graph)[:children]
  end

  def member(boxes, id)
    boxes.find { |box| box[:id] == id }
  end

  # The free space between two boxes along :x or :y.
  def gap(from, to, axis)
    size = axis == :x ? :width : :height
    to[axis] - (from[axis] + from[size])
  end
end

RSpec.describe Sirena::Layout::Flowchart::DirectedPlacement do
  include DirectedPlacementGraphs

  let(:builder) { FlowchartSceneBuilder }

  {
    "TD" => [%w[A B], :y],
    "LR" => [%w[A B], :x],
    "RL" => [%w[B A], :x],
    "BT" => [%w[B A], :y],
  }.each do |direction, ((from, to), axis)|
    it "ranks a #{direction} link's target past its source on #{axis}" do
      found = builder.placed(direction, [%w[A B]])

      expect(builder.clearance(found[from], found[to], axis)).to be >= 0
    end
  end

  it "keeps a sideways link level" do
    found = builder.placed("LR", [%w[A B]])

    expect(found["B"].y).to eq(found["A"].y)
  end

  describe "the box round a subgraph" do
    def size_of(box)
      [box[:width], box[:height]]
    end

    it "keeps 37.5 along the flow and 35 across it round a lone member" do
      boxes = placed(level_graph("DOWN", [subgraph("s", [node("a", 68.390625)])]))

      expect(size_of(member(boxes, "s"))).to eq([143.390625, 124.0])
    end

    it "keeps those margins at both ends of a chain" do
      chain = [node("a"), node("b"), node("c")]
      boxes = placed(level_graph("DOWN", [subgraph("s", chain)],
                                 [%w[a b], %w[b c]]))

      expect(size_of(member(boxes, "s"))).to eq([455.390625, 124.0])
    end

    it "turns the margins with the subgraph's own direction" do
      sub = subgraph("s", [node("a", 68.40625), node("b", 68.921875)],
                     direction: "UP")
      boxes = placed(level_graph("DOWN", [sub], [%w[a b]]))

      expect(size_of(member(boxes, "s"))).to eq([138.921875, 258.0])
    end

    it "keeps half the graph's rank step along the flow of a joint subgraph" do
      boxes = placed(level_graph("DOWN",
                                 [subgraph("s", [node("a", 130.078125)]),
                                  node("b")], [%w[a b]]))

      expect(size_of(member(boxes, "s"))).to eq([200.078125, 104.0])
    end

    it "centres the members in a box widened by its title" do
      titled = subgraph("s", [node("a", 20.0)])
      titled[:labels].first[:width] = 200.0
      held = member(placed(level_graph("DOWN", [titled])), "s")

      expect([held[:width], held[:children].first[:x]]).to eq([240.0, 110.0])
    end
  end

  describe "a subgraph laid out as a graph of its own" do
    def ranks(root, boxes, edges)
      inside = member(placed(level_graph(root, boxes, edges)), "s")[:children]
      [member(inside, "a"), member(inside, "b")]
    end

    let(:chain) { [%w[a b]] }

    it "opens 75 between ranks in a downward graph, running sideways" do
      first, second = ranks("DOWN", [subgraph("s", [node("a"), node("b")])],
                            chain)

      expect([gap(first, second, :x), second[:y]]).to eq([75.0, first[:y]])
    end

    it "opens 75 between ranks in a sideways graph, running downward" do
      first, second = ranks("RIGHT", [subgraph("s", [node("a"), node("b")])],
                            chain)

      expect([gap(first, second, :y), second[:x]]).to eq([75.0, first[:x]])
    end

    it "keeps the graph's 50 for a subgraph a link crosses" do
      boxes = [node("x"), subgraph("s", [node("a"), node("b")])]
      first, second = ranks("DOWN", boxes, [%w[x a], *chain])

      expect(gap(first, second, :y)).to eq(50.0)
    end

    it "opens 100 between the ranks of a subgraph inside one" do
      inner = subgraph("s", [node("a"), node("b")])
      outer = subgraph("outer", [node("c"), node("d"), inner])
      boxes = placed(level_graph("DOWN", [outer], [%w[c d], %w[a b]]))
      held = member(member(boxes, "outer")[:children], "s")[:children]

      expect(gap(member(held, "a"), member(held, "b"), :y)).to eq(100.0)
    end

    it "lays out a subgraph in its own direction, ranks 75 apart" do
      sub = subgraph("s", [node("a"), node("b")], direction: "UP")
      inside = member(placed(level_graph("DOWN", [sub], chain)), "s")[:children]
      above = member(inside, "b")
      below = member(inside, "a")

      expect([gap(above, below, :y), above[:x]]).to eq([75.0, below[:x]])
    end
  end

  context "when a model repeats an id" do
    let(:scene) do
      diagram = Sirena::Diagram::Flowchart.new(direction: "TD")
      diagram.nodes.push(
        Sirena::Diagram::FlowchartNode.new(id: "same", label: "First"),
        Sirena::Diagram::FlowchartNode.new(id: "same", label: "Second"),
      )
      Sirena::Layout::Flowchart.new.to_graph(diagram)
    end

    it "places every node" do
      expect(scene.children.map(&:x)).to all(be_a(Float))
    end

    it "places the nodes apart" do
      expect(scene.children.map { |node| [node.x, node.y] }.uniq.size).to eq(2)
    end
  end
end
