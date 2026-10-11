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

  def box_margins(box)
    outer = [0, 0, box[:width], box[:height]]
    inner = box[:children].map do |child|
      child.values_at(:x, :y, :width, :height)
    end
    FlowchartSceneBuilder.margins(outer, inner)
  end

  def compact_padding
    [be_within(1.0).of(8), be_within(1.0).of(8),
     be_within(0.01).of(25), be_within(0.01).of(25)]
  end

  def disconnected_cluster_boxes
    boxes = [node("a"), node("b"), subgraph("s", [node("c"), node("d")])]
    found = placed(level_graph("DOWN", boxes, [%w[a b], %w[c d]]))
    %w[a b s].map { |id| member(found, id) }
  end

  def center_of(box, axis)
    size = axis == :x ? :width : :height
    box[axis] + (box[size] / 2.0)
  end
end

RSpec.describe Sirena::Layout::Flowchart::DirectedPlacement do
  include DirectedPlacementGraphs

  let(:builder) { FlowchartSceneBuilder }
  let(:subgraph_source) { "flowchart TD\nsubgraph s [T]\nA --> B\nend\n" }

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

  it "matches the reference padding around an independent leaf subgraph" do
    expect(builder.cluster_margins(subgraph_source)).to match(
      [be_within(1.0).of(37.5), be_within(1.0).of(37.5),
       be_within(0.01).of(37.5), be_within(1.0).of(37.5)],
    )
  end

  # The SVG writes whole points, so a width not rounded up can leave less
  # than the 37.5 mmdc keeps beside an independent leaf cluster.
  it "never rounds an independent leaf cluster below its reference padding" do
    source = "flowchart TD\nsubgraph s\nA[Laptop computer]\nend\n"

    expect(builder.cluster_margins(source).first(2)).to all(be >= 37.5)
  end

  it "keeps compact padding when an edge crosses the cluster boundary" do
    boxes = [node("x"), subgraph("s", [node("a"), node("b")])]
    graph = level_graph("DOWN", boxes, [%w[x a], %w[a b]])
    cluster = member(placed(graph), "s")

    expect(box_margins(cluster)).to match(compact_padding)
  end

  it "keeps compact padding around a leaf cluster nested inside another" do
    inner = subgraph("inner", [node("a"), node("b")])
    outer = subgraph("outer", [inner])
    held = member(member(placed(level_graph("DOWN", [outer])), "outer")
                    .fetch(:children), "inner")

    expect(box_margins(held)).to match(compact_padding)
  end

  it "packs a disconnected cluster left of a straight linked component" do
    a, b, cluster = disconnected_cluster_boxes

    expect([a[:x], center_of(a, :y), gap(cluster, a, :x)])
      .to eq([b[:x], center_of(cluster, :y), 50.0])
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

  context "when boxes beside a subgraph have an edge into it" do
    let(:source) do
      "flowchart TB\nsubgraph A\ndirection RL\nb-->B\na\nend\na-->c\n" \
        "subgraph B\ndirection LR\nc\nend\n"
    end

    # mmdc: B is 196 tall, spanning the two boxes that point at it.
    it "stretches the subgraph to cover them" do
      xml = Sirena.render(source)
      height = xml[/<g id="cluster-B">\s*<rect[^>]*\bheight="([^"]*)"/, 1]

      expect(height.to_f).to eq(196.0)
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
