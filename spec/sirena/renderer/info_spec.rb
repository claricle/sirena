# frozen_string_literal: true

require "spec_helper"
require "sirena/renderer/info"

RSpec.describe Sirena::Renderer::Info do
  subject(:svg) { described_class.new.render(scene) }

  let(:show_info) { false }
  let(:scene) do
    Sirena::Layout::Info.from_graph({ show_info: show_info })
  end

  it "refuses legacy Hash geometry at the typed Scene boundary" do
    expect { described_class.new.render(show_info: false) }
      .to raise_error(NoMethodError)
  end

  it "renders only the mmdc version text on mmdc's 400x100 canvas" do
    expect(rendered_geometry).to eq(expected_geometry)
  end

  it "renders the same version text when showInfo is enabled" do
    enabled_scene = Sirena::Layout::Info.from_graph({ show_info: true })
    enabled_svg = described_class.new.render(enabled_scene)
    label = enabled_svg.children.grep(Sirena::Svg::Text).first

    expect(Array(label.content).join).to eq("v11.12.0")
  end

  def text_geometry(label)
    [label.x, label.y, Array(label.content).join, label.font_size]
  end

  def rendered_geometry
    [svg.width, svg.height, svg.view_box,
     svg.children.grep(Sirena::Svg::Rect).size,
     text_geometry(svg.children.grep(Sirena::Svg::Text).first)]
  end

  def expected_geometry
    [400.0, 100.0, "0 0 400 100", 0, [100.0, 40.0, "v11.12.0", "32"]]
  end
end
