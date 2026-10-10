# frozen_string_literal: true

require "spec_helper"
require "sirena/renderer/error"

RSpec.describe Sirena::Renderer::Error do
  subject(:svg) { described_class.new.render(message: message) }

  let(:message) { "Dependency missing" }
  let(:dark) { Sirena::Theme::Registry.get(:dark) }
  let(:themed) { described_class.new(theme: dark).render(message: message) }
  let(:theme_colors) do
    [dark.colors.surface, dark.colors.error, dark.colors.edge_stroke,
     dark.colors.background]
  end

  it "renders the error canvas, box, icon, and explicit message geometry" do
    expect(rendered_geometry).to eq(expected_geometry)
  end

  it "falls back to the default error message" do
    default_svg = described_class.new.render(message: nil)
    label = default_svg.children.grep(Sirena::Svg::Text).first

    expect(Array(label.content).join).to eq("Error")
  end

  it "uses semantic colors from the active theme" do
    expect(themed.to_xml).to include(*theme_colors)
  end

  def rendered_geometry
    box, mark = children_of(Sirena::Svg::Rect)
    ring, dot = children_of(Sirena::Svg::Circle)
    [document_geometry, box_geometry(box), circle_geometry(ring),
     mark_geometry(mark), circle_geometry(dot),
     children_of(Sirena::Svg::Text).map { |label| text_geometry(label) }]
  end

  def children_of(type)
    svg.children.grep(type)
  end

  def expected_geometry
    [[2412.0, 512.0, "0 0 2412 512"],
     [0.0, 0.0, 2412.0, 512.0], [256.0, 256.0, 256.0],
     [240.0, 128.0, 32.0, 192.0], [256.0, 384.0, 16.0],
     [[1440.0, 250.0, "middle", "Dependency missing"],
      [1250.0, 400.0, "middle", "mermaid version 11.12.0"]]]
  end

  def document_geometry
    [svg.width, svg.height, svg.view_box]
  end

  def box_geometry(box)
    [box.x, box.y, box.width, box.height]
  end

  def circle_geometry(circle)
    [circle.cx, circle.cy, circle.r]
  end

  def mark_geometry(mark)
    [mark.x, mark.y, mark.width, mark.height]
  end

  def text_geometry(label)
    [label.x, label.y, label.text_anchor, Array(label.content).join]
  end
end
