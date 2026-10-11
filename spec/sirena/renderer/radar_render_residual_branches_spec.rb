# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::Radar, "#render" do
  subject(:renderer) { described_class.new }

  let(:source) { "radar-beta\n  axis a, b, c\n  curve c1{1, 2, 3}\n" }
  let(:scene) do
    diagram = Sirena::Parser::Radar.new.parse(source)
    Sirena::Layout::Radar.new.call(diagram)
  end
  let(:polygons) { renderer.render(scene).children.grep(Sirena::Svg::Path) }

  it "draws a path for a curve" do
    expect(polygons.size).to eq(1)
  end

  it "draws no path for a curve without points" do
    scene.curves.first.points = []

    expect(polygons).to be_empty
  end

  it "paints curves from the theme's radar palette" do
    renderer.theme = Sirena::Theme.new(
      colors: { radar_palette: ["#123456"] },
    )

    expect([polygons.first.fill, polygons.first.stroke])
      .to eq(["#123456", "#123456"])
  end
end
