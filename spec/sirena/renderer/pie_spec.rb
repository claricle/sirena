# frozen_string_literal: true

require "spec_helper"
require "sirena/renderer/pie"

RSpec.describe Sirena::Renderer::Pie do
  subject(:svg) { described_class.new.render(scene) }

  let(:graph) { { slices: [] } }
  let(:scene) { Sirena::Layout::Pie.from_graph(graph) }

  it "rejects a bare positioned Hash" do
    expect { described_class.new.render(graph) }.to raise_error(NoMethodError)
  end

  it "uses the compact canvas and draws only the ring for an empty pie" do
    expect([svg.width, svg.height, svg.view_box, svg.children.map(&:class)])
      .to eq([450.0, 450.0, "0 0 450 450", [Sirena::Svg::Circle]])
  end

  it "centers the title above the pie" do
    graph[:title] = "Distribution"
    title = svg.children.grep(Sirena::Svg::Text).first

    expect([svg.height, title.x, title.y, text(title)]).to eq(
      [450.0, 225.0, 25.0, "Distribution"],
    )
  end

  it "renders small and large arcs with percentage labels" do
    graph.merge!(slices: slices, show_data: true)
    expect(rendered_arcs).to match(expected_arcs)
  end

  it "captions the legend with the label alone without showData" do
    graph.merge!(slices: slices, show_data: false)

    expect(rendered_labels).to eq(["75%", "25%", "Large", "Small"])
  end

  it "copies the ring and legend swatch geometry from the Scene" do
    graph[:slices] = slices
    scene.ring.cx = 17
    scene.legend.first.width = 9

    expect([svg.children.first.cx, legend_rect.width]).to eq([17.0, 9.0])
  end

  def rendered_arcs
    paths = svg.children.grep(Sirena::Svg::Path)
    [paths.map(&:d), rendered_labels]
  end

  def expected_arcs
    [
      [include("A 185 185 0 1 1"), include("A 185 185 0 0 1")],
      ["75%", "25%", "Large [3]", "Small [1]"],
    ]
  end

  def rendered_labels
    svg.children.grep(Sirena::Svg::Text).map { |label| text(label) }
  end

  def legend_rect
    svg.children.grep(Sirena::Svg::Rect).first
  end

  def slices
    [
      { label: "Large", value: 3, percentage: 75.0, angle: 270.0 },
      { label: "Small", value: 1, percentage: 25.0, angle: 90.0 },
    ]
  end

  def text(element)
    Array(element.content).join
  end
end
