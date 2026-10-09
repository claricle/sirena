# frozen_string_literal: true

require "spec_helper"
require "sirena/renderer/error"

RSpec.describe Sirena::Renderer::Error do
  subject(:svg) { described_class.new.render(message: message) }

  let(:message) { "Dependency missing" }

  it "renders the error canvas, box, icon, and explicit message geometry" do
    expect(rendered_geometry).to eq(expected_geometry)
  end

  it "falls back to the default error message" do
    default_svg = described_class.new.render(message: nil)
    label = default_svg.children.grep(Sirena::Svg::Text).first

    expect(Array(label.content).join).to eq("Error")
  end

  def rendered_geometry
    box, mark = children_of(Sirena::Svg::Rect)
    ring, dot = children_of(Sirena::Svg::Circle)
    [document_geometry, box_geometry(box), circle_geometry(ring),
     mark_geometry(mark), circle_geometry(dot),
     text_geometry(children_of(Sirena::Svg::Text).first)]
  end

  def children_of(type)
    svg.children.grep(type)
  end

  def expected_geometry
    [[500.0, 220.0, "0 0 500 220"],
     [50.0, 50.0, 400.0, 120.0], [100.0, 110.0, 20.0],
     [98.0, 100.0, 4.0, 12.0], [100.0, 116.0, 2.0],
     [140.0, 105.0, "Dependency missing"]]
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
    [label.x, label.y, Array(label.content).join]
  end
end
