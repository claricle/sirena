# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::Radar, "#render" do
  let(:source) { "radar-beta\n  axis a, b, c\n  curve c1{1, 2, 3}\n" }
  let(:scene) do
    diagram = Sirena::Parser::Radar.new.parse(source)
    Sirena::Layout::Radar.new.call(diagram)
  end
  let(:polygons) { described_class.new.render(scene).children.grep(Sirena::Svg::Polygon) }

  it "draws a polygon for a curve" do
    expect(polygons.size).to eq(1)
  end

  it "draws no polygon for a curve without points" do
    scene.curves.first.points = []

    expect(polygons).to be_empty
  end
end
