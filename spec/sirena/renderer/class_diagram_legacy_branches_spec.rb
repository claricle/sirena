# frozen_string_literal: true

require "spec_helper"

module ClassDiagramLegacySnapshots
  def render_graph(children:, edges: [])
    described_class.new.render(id: "legacy", children: children, edges: edges)
  end

  def relationship(svg, edge_id)
    svg.children.find { |child| child.id == "rel-#{edge_id}" }
  end

  def typed_edge(type)
    {
      id: type, sources: ["A"], targets: ["B"],
      metadata: { relationship_type: type }
    }
  end

  def relationship_summary(group)
    line = group.children.grep(Sirena::Svg::Line).first
    polygon = group.children.grep(Sirena::Svg::Polygon).first
    point_count = polygon ? polygon.points.split.length : nil
    [line.stroke_dasharray, point_count, polygon&.fill]
  end

  def relationship_type_snapshot
    edges = relationship_types.map { |type| typed_edge(type) }
    svg = render_graph(children: nodes, edges: edges)
    relationship_types.to_h do |type|
      [type, relationship_summary(relationship(svg, type))]
    end
  end

  def text_contents(texts)
    texts.map { |text| Array(text.content).join }
  end

  def labeled_relationship_snapshot
    svg = render_graph(children: nodes, edges: labeled_edges)
    groups = svg.children.select { |child| child.id&.start_with?("rel-") }
    texts = groups.first.children.grep(Sirena::Svg::Text)
    [groups.map(&:id), text_contents(texts), texts.map(&:text_anchor)]
  end

  def fallback_group
    svg = render_graph(children: [{ id: "Fallback" }])
    [svg, svg.children.find { |child| child.id == "class-Fallback" }]
  end

  def fallback_snapshot
    svg, group = fallback_group
    box = group.children.grep(Sirena::Svg::Rect).first
    [svg.width, svg.height, box.x, box.y, box.width, box.height,
     text_contents(group.children.grep(Sirena::Svg::Text))]
  end
end

RSpec.describe Sirena::Renderer::ClassDiagram do
  include ClassDiagramLegacySnapshots

  let(:nodes) do
    [
      { id: "A", x: 10, y: 20, width: 120, height: 80 },
      { id: "B", x: 210, y: 20, width: 120, height: 80 },
    ]
  end
  let(:relationship_types) do
    %w[association dependency inheritance realization composition aggregation]
  end
  let(:labeled_edges) do
    [
      { id: "missing-source", sources: ["missing"], targets: ["B"] },
      { id: "missing-target", sources: ["A"], targets: ["missing"] },
      {
        id: "labeled", sources: ["A"], targets: ["B"],
        labels: [
          { text: "owns" },
          { text: "one", position: "source" },
          { text: "many", position: "target" },
        ]
      },
    ]
  end
  let(:expected_dispatch) do
    {
      "association" => [nil, nil, nil],
      "dependency" => ["5,5", nil, nil],
      "inheritance" => [nil, 3, "#000000"],
      "realization" => [nil, 3, "#ffffff"],
      "composition" => [nil, 4, "#000000"],
      "aggregation" => [nil, 4, "#ffffff"],
    }
  end

  it "uses released geometry and content fallbacks for sparse nodes" do
    expect(fallback_snapshot)
      .to eq([230, 180, 0, 0, 150, 100, ["Fallback"]])
  end

  it "dispatches every single relationship type independently" do
    expect(relationship_type_snapshot).to eq(expected_dispatch)
  end

  it "drops missing endpoints and positions all three labels independently" do
    expect(labeled_relationship_snapshot)
      .to eq([["rel-labeled"], %w[owns one many], ["middle", nil, "end"]])
  end
end
