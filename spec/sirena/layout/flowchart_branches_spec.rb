# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Flowchart do
  def node(id, x, shape)
    {
      id: id, x: x, y: 20, width: 80, height: 40,
      labels: [{ text: id }], metadata: { shape: shape }
    }
  end

  def edge(id, source, target, arrow_type)
    {
      id: id, sources: [source], targets: [target],
      metadata: { arrow_type: arrow_type }
    }
  end

  it "converts every supported outline into final shape geometry" do
    shapes = %w[rounded stadium circle double_circle rhombus hexagon mystery]
    children = shapes.each_with_index.map do |shape, index|
      node(shape, index * 100, shape)
    end

    scene = described_class.from_graph({ children: children, edges: [] })
    by_id = scene.children.to_h { |child| [child.id, child] }

    expect(shapes.map { |shape| by_id.fetch(shape).shape_kind })
      .to eq(%w[rounded rounded circle circle rhombus hexagon rect])
    expect(by_id.fetch("rounded").corner_radius).to eq(20.0)
    expect(by_id.fetch("circle").radius).to eq(20.0)
    expect(by_id.fetch("rhombus").shape_points.split.length).to eq(4)
    expect(by_id.fetch("hexagon").shape_points.split.length).to eq(6)
    expect(by_id.fetch("mystery").shape_points).to be_nil
  end

  it "builds arrow, circle, cross, and double-ended heads" do
    children = [node("A", 0, "rect"), node("B", 200, "rect")]
    edges = [
      edge("arrow", "A", "B", "arrow"),
      edge("circle", "A", "B", "circle"),
      edge("cross", "A", "B", "cross"),
      edge("both", "A", "B", "arrow_both"),
      edge("plain", "A", "B", "line"),
    ]

    heads = described_class.from_graph({ children: children, edges: edges })
      .edges.to_h { |item| [item.id, item.heads] }

    expect(heads.fetch("arrow").first.shape).to eq("arrow")
    expect(heads.fetch("arrow").first.points.split.length).to eq(3)
    expect(heads.fetch("circle").first)
      .to have_attributes(shape: "circle", radius: 5.5)
    expect(heads.fetch("cross").first.lines.length).to eq(2)
    expect(heads.fetch("both").map(&:shape)).to eq(%w[arrow arrow])
    expect(heads.fetch("plain")).to be_empty
  end

  it "reserves page space for an upward labelled self-loop" do
    graph = {
      id: "loops",
      layoutOptions: { "elk.direction" => "UP" },
      children: [node("A", 0, "rect")],
      edges: [
        edge("loop", "A", "A", "arrow").merge(
          labels: [{ text: "self loop", width: 70, height: 16 }],
        ),
      ],
    }

    scene = described_class.from_graph(graph)
    loop_edge = scene.edges.first

    expect(scene.children.first.y).to be > 20
    expect(loop_edge.sections.first.bend_points.length).to eq(2)
    expect(loop_edge.path).to include(" L ")
    expect(loop_edge.labels.first.y).to be >= 0
    expect([scene.width, scene.height]).to all(be > 100)
  end
end
