# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::ErDiagram do
  let(:renderer) { described_class.new }
  let(:nodes) do
    %w[A B].map.with_index do |id, index|
      {
        id: id, x: index * 200, y: 0, width: 120, height: 60,
        metadata: { name: id, attributes: [] }
      }
    end
  end
  let(:endpoint_edges) do
    [
      { id: "missing-source", sources: ["missing"], targets: ["B"] },
      { id: "missing-target", sources: ["A"], targets: ["missing"] },
      { id: "kept", sources: ["A"], targets: ["B"] },
    ]
  end
  let(:adornment_edges) do
    [
      {
        id: "plain", sources: ["A"], targets: ["B"],
        metadata: { relationship_type: "identifying" }
      },
      {
        id: "source-only", sources: ["A"], targets: ["B"],
        labels: [{ text: "owns" }],
        metadata: {
          relationship_type: "identifying",
          cardinality_from: "one_or_more",
        }
      },
      {
        id: "target-only", sources: ["A"], targets: ["B"],
        metadata: {
          relationship_type: "identifying",
          cardinality_to: "zero_or_one",
        }
      },
    ]
  end

  def render_edges(edges)
    renderer.render(id: "er", children: nodes, edges: edges)
  end

  def relationship(svg, edge_id)
    svg.children.find { |child| child.id == "rel-#{edge_id}" }
  end

  def shape_counts(group)
    [Sirena::Svg::Line, Sirena::Svg::Circle, Sirena::Svg::Text].map do |type|
      group.children.grep(type).length
    end
  end

  def adornment_snapshot
    svg = render_edges(adornment_edges)
    adornment_edges.to_h do |edge|
      [edge[:id], shape_counts(relationship(svg, edge[:id]))]
    end
  end

  it "rejects absent endpoints and defaults a kept relationship to dashed" do
    svg = render_edges(endpoint_edges)
    groups = svg.children.select { |child| child.id&.start_with?("rel-") }
    line = groups.first.children.grep(Sirena::Svg::Line).first

    expect([groups.map(&:id), line.stroke_dasharray])
      .to eq([["rel-kept"], "5,5"])
  end

  it "keeps absent and one-sided relationship adornments independent" do
    expect(adornment_snapshot).to eq(
      "plain" => [1, 0, 0],
      "source-only" => [5, 0, 1],
      "target-only" => [2, 1, 0],
    )
  end
end
