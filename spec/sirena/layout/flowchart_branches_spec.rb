# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Flowchart do
  def node(id, x_position, shape)
    {
      id: id, x: x_position, y: 20, width: 80, height: 40,
      labels: [{ text: id }], metadata: { shape: shape }
    }
  end

  def edge(id, source, target, arrow_type)
    {
      id: id, sources: [source], targets: [target],
      metadata: { arrow_type: arrow_type }
    }
  end

  describe "supported outlines" do
    let(:shapes) do
      %w[rounded stadium circle double_circle rhombus hexagon mystery]
    end
    let(:children) do
      shapes.each_with_index.map do |shape, index|
        node(shape, index * 100, shape)
      end
    end
    let(:nodes) do
      described_class.from_graph({ children: children, edges: [] })
        .children.to_h { |child| [child.id, child] }
    end

    it "maps every outline to final shape geometry" do
      expect(shapes.map { |shape| nodes.fetch(shape).shape_kind })
        .to eq(%w[rounded rounded circle circle rhombus hexagon rect])
    end

    it "rounds rounded nodes" do
      expect(nodes.fetch("rounded").corner_radius).to eq(20.0)
    end

    it "sizes circle nodes" do
      expect(nodes.fetch("circle").radius).to eq(20.0)
    end

    it "builds rhombus points" do
      expect(nodes.fetch("rhombus").shape_points.split.length).to eq(4)
    end

    it "builds hexagon points" do
      expect(nodes.fetch("hexagon").shape_points.split.length).to eq(6)
    end

    it "leaves fallback rectangles without shape points" do
      expect(nodes.fetch("mystery").shape_points).to be_nil
    end
  end

  describe "edge heads" do
    let(:children) do
      [node("A", 0, "rect"), node("B", 200, "rect")]
    end
    let(:edges) do
      [
        edge("arrow", "A", "B", "arrow"),
        edge("circle", "A", "B", "circle"),
        edge("cross", "A", "B", "cross"),
        edge("both", "A", "B", "arrow_both"),
        edge("plain", "A", "B", "line"),
      ]
    end
    let(:heads) do
      described_class.from_graph({ children: children, edges: edges })
        .edges.to_h { |item| [item.id, item.heads] }
    end

    it "builds arrow heads" do
      expect(heads.fetch("arrow").first.shape).to eq("arrow")
    end

    it "builds triangular arrow geometry" do
      expect(heads.fetch("arrow").first.points.split.length).to eq(3)
    end

    it "builds circle heads" do
      expect(heads.fetch("circle").first)
        .to have_attributes(shape: "circle", radius: 5.5)
    end

    it "builds cross heads" do
      expect(heads.fetch("cross").first.lines.length).to eq(2)
    end

    it "builds double-ended arrow heads" do
      expect(heads.fetch("both").map(&:shape)).to eq(%w[arrow arrow])
    end

    it "keeps plain edges headless" do
      expect(heads.fetch("plain")).to be_empty
    end
  end

  describe "an upward labelled self-loop" do
    let(:graph) do
      {
        id: "loops",
        layoutOptions: { "elk.direction" => "UP" },
        children: [node("A", 0, "rect")],
        edges: [loop_edge],
      }
    end
    let(:loop_edge) do
      edge("loop", "A", "A", "arrow").merge(
        labels: [{ text: "self loop", width: 70, height: 16 }],
      )
    end
    let(:scene) { described_class.from_graph(graph) }

    it "reserves space above its node" do
      expect(scene.children.first.y).to be > 20
    end

    it "routes through two bend points" do
      expect(scene.edges.first.sections.first.bend_points.length).to eq(2)
    end

    it "builds a segmented path" do
      expect(scene.edges.first.path).to include(" L ")
    end

    it "keeps its label on the page" do
      expect(scene.edges.first.labels.first.y).to be >= 0
    end

    it "expands the page dimensions" do
      expect([scene.width, scene.height]).to all(be > 100)
    end
  end
end
