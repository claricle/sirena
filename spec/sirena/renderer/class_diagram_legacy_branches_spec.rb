# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::ClassDiagram, "legacy graph branches" do
  let(:renderer) { described_class.new }
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
        ],
      },
    ]
  end

  def render_graph(children:, edges: [])
    renderer.render(id: "legacy", children: children, edges: edges)
  end

  def relationship(svg, edge_id)
    svg.children.find { |child| child.id == "rel-#{edge_id}" }
  end

  def relationship_type_snapshot
    edges = relationship_types.map do |type|
      {
        id: type, sources: ["A"], targets: ["B"],
        metadata: { relationship_type: type },
      }
    end
    svg = render_graph(children: nodes, edges: edges)
    relationship_types.to_h do |type|
      group = relationship(svg, type)
      line = group.children.grep(Sirena::Svg::Line).first
      polygon = group.children.grep(Sirena::Svg::Polygon).first
      [type, [line.stroke_dasharray, polygon&.points&.split&.length,
              polygon&.fill]]
    end
  end

  def labeled_relationship_snapshot
    svg = render_graph(children: nodes, edges: labeled_edges)
    groups = svg.children.select { |child| child.id&.start_with?("rel-") }
    texts = groups.first.children.grep(Sirena::Svg::Text)
    [groups.map(&:id), texts.map { |text| Array(text.content).join },
     texts.map(&:text_anchor)]
  end

  it "uses released geometry and content fallbacks for sparse nodes" do
    svg = render_graph(children: [{ id: "Fallback" }])
    group = svg.children.find { |child| child.id == "class-Fallback" }
    box = group.children.grep(Sirena::Svg::Rect).first
    texts = group.children.grep(Sirena::Svg::Text)

    expect([svg.width, svg.height, box.x, box.y, box.width, box.height,
            texts.map { |text| Array(text.content).join }])
      .to eq([230, 180, 0, 0, 150, 100, ["Fallback"]])
  end

  it "dispatches every single relationship type independently" do
    expect(relationship_type_snapshot).to eq(
      "association" => [nil, nil, nil],
      "dependency" => ["5,5", nil, nil],
      "inheritance" => [nil, 3, "#000000"],
      "realization" => [nil, 3, "#ffffff"],
      "composition" => [nil, 4, "#000000"],
      "aggregation" => [nil, 4, "#ffffff"],
    )
  end

  it "drops missing endpoints and positions all three labels independently" do
    expect(labeled_relationship_snapshot)
      .to eq([["rel-labeled"], %w[owns one many], ["middle", nil, "end"]])
  end
end
