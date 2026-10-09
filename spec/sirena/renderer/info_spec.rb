# frozen_string_literal: true

require "spec_helper"
require "sirena/renderer/info"

RSpec.describe Sirena::Renderer::Info do
  subject(:svg) { described_class.new.render(show_info: show_info) }

  let(:show_info) { false }

  it "renders the default message on the fixed info canvas" do
    expect(rendered_geometry).to eq(expected_geometry)
  end

  it "renders the enabled showInfo message" do
    enabled_svg = described_class.new.render(show_info: true)
    label = enabled_svg.children.grep(Sirena::Svg::Text).first

    expect(Array(label.content).join).to eq("Info: showInfo enabled")
  end

  def box_geometry(box)
    [box.x, box.y, box.width, box.height, box.rx]
  end

  def text_geometry(label)
    [label.x, label.y, Array(label.content).join]
  end

  def rendered_geometry
    box = svg.children.grep(Sirena::Svg::Rect).first
    label = svg.children.grep(Sirena::Svg::Text).first
    [svg.width, svg.height, svg.view_box,
     box_geometry(box), text_geometry(label)]
  end

  def expected_geometry
    [500.0, 200.0, "0 0 500 200",
     [50.0, 50.0, 400.0, 100.0, 8.0],
     [250.0, 105.0, "Info"]]
  end
end
