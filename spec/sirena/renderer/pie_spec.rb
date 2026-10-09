# frozen_string_literal: true

require "spec_helper"
require "sirena/renderer/pie"

RSpec.describe Sirena::Renderer::Pie do
  subject(:svg) { described_class.new.render(graph) }

  let(:graph) { { slices: [] } }

  it "uses the compact canvas and emits no marks for an empty pie" do
    expect([svg.width, svg.height, svg.view_box, svg.children]).to eq(
      [500.0, 400.0, "0 0 500 400", []],
    )
  end

  it "adds title space and centers the title" do
    graph[:title] = "Distribution"
    title = svg.children.grep(Sirena::Svg::Text).first

    expect([svg.height, title.x, title.y, text(title)]).to eq(
      [460.0, 250.0, 40.0, "Distribution"],
    )
  end

  it "renders small and large arcs with percentage labels" do
    graph.merge!(slices: slices, show_data: true)
    expect(rendered_arcs).to match(expected_arcs)
  end

  it "keeps labels free of values when showData is disabled" do
    graph.merge!(slices: slices, show_data: false)

    expect(rendered_labels).to eq(["Large", "Small"])
  end

  def rendered_arcs
    paths = svg.children.grep(Sirena::Svg::Path)
    [paths.map(&:d), rendered_labels]
  end

  def expected_arcs
    [
      [include("A 150 150 0 1 1"), include("A 150 150 0 0 1")],
      ["Large: 75.0%", "Small: 25.0%"],
    ]
  end

  def rendered_labels
    svg.children.grep(Sirena::Svg::Text).map { |label| text(label) }
  end

  def slices
    [
      { label: "Large", percentage: 75.0, angle: 270.0 },
      { label: "Small", percentage: 25.0, angle: 90.0 },
    ]
  end

  def text(element)
    Array(element.content).join
  end
end
