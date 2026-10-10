# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Flowchart do
  let(:graphs) { FlowchartCoverageGraphs }

  def coordinates(scene)
    scene.children.map { |node| [node.id, node.x, node.y] }
  end

  describe "edges that name no endpoint" do
    let(:children) do
      [graphs.node("A", [0, 0], [100, 200]), graphs.node("B", [200, 0])]
    end
    let(:scene) do
      graphs.scene(
        children,
        [graphs.edge("ok", "A", "B"),
         { id: "no_source", targets: ["B"] },
         { id: "no_target", sources: ["A"] }],
      )
    end

    it "reserves no loop room above their node" do
      up = graphs.scene(children, [{ id: "no_target", sources: ["A"] }], "UP")

      expect(up.children.first.y).to eq(0)
    end

    it "draws only the edge with both ends" do
      expect(scene.edges.map(&:id)).to eq(["ok"])
    end
  end

  describe "a page shifted by an upward self-loop" do
    let(:children) { [graphs.node("A", [0, 0]), graphs.node("B", [200, 0])] }
    let(:loop_edge) { graphs.edge("loop", "A", "A") }
    let(:bare) { graphs.edge("bare", "A", "B").except(:metadata) }
    let(:bendless) { graphs.edge("bendless", "A", "B").merge(sections: [{}]) }

    it "keeps an edge with no sections aligned to the moved nodes" do
      scene = graphs.scene(children, [loop_edge, bare], "UP")
      node = scene.children.first

      expect(scene.edges.last.sections.first.start_point.y)
        .to eq(node.center_y)
    end

    it "keeps an edge with a bendless section aligned too" do
      scene = graphs.scene(children, [loop_edge, bendless], "UP")
      node = scene.children.first

      expect(scene.edges.last.sections.first.start_point.y)
        .to eq(node.center_y)
    end
  end

  describe "bend points on a shifted page" do
    let(:children) { [graphs.node("A", [0, 0]), graphs.node("B", [200, 0])] }
    let(:bent) do
      graphs.edge("bent", "A", "B").merge(
        sections: [{ bendPoints: [{ x: 150, y: 25 }] }],
      )
    end
    let(:scene) do
      graphs.scene(children, [graphs.edge("loop", "A", "A"), bent], "UP")
    end

    it "move with the nodes" do
      bend = scene.edges.last.sections.first.bend_points.first

      expect(bend.y).to eq(25 + scene.children.first.y)
    end
  end

  describe "self-loops that overflow on one side only" do
    let(:children) { [graphs.node("A", [0, 0]), graphs.node("B", [300, 0])] }
    let(:loops) { [graphs.edge("a", "A", "A"), graphs.edge("b", "B", "B")] }

    it "shifts the page by the leftmost loop" do
      scene = graphs.scene(children, loops, "LEFT")

      expect(scene.children.first.x).to be > 0
    end
  end

  describe "two self-loops" do
    let(:children) do
      [graphs.node("A", [0, 0], [100, 200]), graphs.node("B", [300, 0])]
    end
    let(:scene) do
      graphs.scene(children, [graphs.edge("a", "A", "A"),
                              graphs.edge("b", "B", "B")])
    end

    it "sizes the page for the deeper of the two loops" do
      expect(scene.height).to be >= 285
    end
  end

  describe "a cross head whose tip meets its bend" do
    let(:edge) do
      graphs.edge("x", "A", "B", "cross").merge(
        sections: [{ bendPoints: [{ x: 200, y: 25 }] }],
      )
    end
    let(:scene) do
      graphs.scene([graphs.node("A", [0, 0]), graphs.node("B", [200, 0])],
                   [edge])
    end

    it "draws the arms along the diagonals" do
      line = scene.edges.first.heads.first.lines.first

      expect([line.x1, line.y1, line.x2, line.y2])
        .to eq([195.5, 20.5, 204.5, 29.5])
    end
  end

  describe "a hexagon left along a horizontal edge" do
    let(:scene) do
      graphs.scene([graphs.node("A", [0, 0], [100, 50], "hexagon"),
                    graphs.node("B", [200, 0])], [graphs.edge("h", "A", "B")])
    end

    it "starts on the hexagon's right-hand point" do
      expect(scene.edges.first.sections.first.start_point.x).to eq(100.0)
    end
  end

  describe "a graph without settings" do
    let(:graph) { graphs.settingless_graph("flowchart LR\nA-->B") }
    let(:scene) { described_class.new.call(graph) }

    it "takes the graph id as the scene id" do
      expect(scene.id).to eq(graph.id)
    end

    it "places the nodes where the full graph places them" do
      full = graphs.settingless_graph("flowchart LR\nA-->B", keep: true)

      expected = coordinates(described_class.new.call(full))

      expect(coordinates(scene)).to eq(expected)
    end
  end
end
