# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::ClassDiagram do
  let(:children) do
    [
      { id: "A", x: 0, y: 0, width: 120, height: 70 },
      { id: "B", x: 240, y: 0, width: 120, height: 70 },
    ]
  end

  def relation(id, metadata = {}, sections: nil)
    edge = {
      id: id, sources: ["A"], targets: ["B"],
      metadata: metadata
    }
    edge[:sections] = sections if sections
    edge
  end

  it "accepts snake-case and camel-case routed coordinates" do
    snake = {
      start_point: { x: 120, y: 20 }, end_point: { x: 240, y: 20 },
      bend_points: [{ x: 180, y: 30 }]
    }
    camel = {
      "startPoint" => { x: 120, y: 40 },
      "endPoint" => { x: 240, y: 40 },
      "bendPoints" => [{ x: 180, y: 50 }],
    }
    edges = [
      relation("snake", sections: [snake]),
      relation("camel", sections: [camel]),
      relation("fallback"),
    ]

    scene_edges = described_class.from_graph({ children: children, edges: edges })
      .edges.to_h { |edge| [edge.id, edge.sections.first] }

    expect(scene_edges.fetch("snake").bend_points.first.y).to eq(30.0)
    expect(scene_edges.fetch("camel").bend_points.first.y).to eq(50.0)
    expect(scene_edges.fetch("fallback").start_point.x).to eq(120.0)
    expect(scene_edges.fetch("fallback").end_point.x).to eq(240.0)
  end

  it "maps relation types to marker fill and line style" do
    types = %w[inheritance realization composition aggregation dependency]
    edges = types.map do |type|
      relation(type, { relationship_type: type })
    end

    by_type = described_class.from_graph({ children: children, edges: edges })
      .edges.to_h { |edge| [edge.id, edge] }

    expect(by_type.fetch("inheritance").markers.first.fill).to eq("#000000")
    expect(by_type.fetch("realization").markers.first.fill).to eq("#ffffff")
    expect(by_type.fetch("composition").markers.first.fill).to eq("#000000")
    expect(by_type.fetch("aggregation").markers.first.fill).to eq("#ffffff")
    expect(by_type.fetch("dependency").markers).to be_empty
    expect(by_type.fetch("dependency").dashed).to be(true)
  end

  it "supports mixed terminal markers and their explicit dashed style" do
    metadata = {
      start_marker: "composition",
      end_marker: "dependency",
      dashed: true,
    }

    mixed_edges = [relation("mixed", metadata)]
    graph = {
      children: children,
      edges: mixed_edges,
    }
    edge = described_class.from_graph(graph).edges.first

    expect(edge.markers.map(&:fill)).to eq(%w[#000000 #000000])
    expect(edge.markers.map { |marker| marker.points.split.length })
      .to eq([4, 4])
    expect(edge.dashed).to be(true)
  end

  it "keeps an empty class compartment structurally complete" do
    node = described_class.from_graph({ children: [children.first], edges: [] })
      .children.first

    expect(node.name.text).to eq("A")
    expect(node.stereotype).to be_nil
    expect(node.attributes).to be_empty
    expect(node.method_rows).to be_empty
    expect(node.labels.map(&:text)).to eq(["A"])
    expect(node.separators.length).to eq(1)
  end
end
