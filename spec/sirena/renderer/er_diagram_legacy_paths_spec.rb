# frozen_string_literal: true

require "spec_helper"

module ErDiagramLegacyPathHelpers
  module_function

  NODES = %w[A B].map.with_index do |id, index|
    {
      id: id, x: index * 200, y: 0, width: 120, height: 60,
      metadata: { name: id, attributes: [] }
    }
  end.freeze

  def render_edge(edge)
    graph = { id: "er", children: NODES, edges: [edge] }
    Sirena::Renderer::ErDiagram.new.render(graph).children
      .find { |item| item.id == "rel-#{edge[:id]}" }
  end

  def cardinality_edge(cardinality)
    {
      id: "card", sources: ["A"], targets: ["B"],
      metadata: { cardinality_from: cardinality, cardinality_to: cardinality }
    }
  end

  def font_sizes(source, theme)
    svg = Sirena::Engine.new(theme: theme).render(source)
    svg.scan(/font-size="([^"]*)"/).flatten.uniq
  end
end

RSpec.describe Sirena::Renderer::ErDiagram do
  let(:helpers) { ErDiagramLegacyPathHelpers }

  it "drops a legacy edge that names no endpoints" do
    expect(helpers.render_edge({ id: "bare" })).to be_nil
  end

  it "draws only the line for an unknown cardinality" do
    group = helpers.render_edge(helpers.cardinality_edge("bogus"))
    expect(group.children.map(&:class)).to eq([Sirena::Svg::Line])
  end

  it "keeps a fractional theme font size fractional" do
    sizes = helpers.font_sizes("erDiagram\nA ||--o{ B : owns\n",
                               typography: { font_size_small: 12.5 })
    expect(sizes).to include("12.5")
  end

  it "writes a whole-number theme font size without a fraction" do
    sizes = helpers.font_sizes("erDiagram\nA ||--o{ B : owns\n",
                               typography: { font_size_small: 13.0 })
    expect(sizes).to include("13")
  end
end
