# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Radar, "#call ring outlines" do
  let(:source) do
    "radar-beta\n  axis a, b, c\n  curve c1{1, 2, 3}\n  ticks 3\n  " \
      "graticule polygon\n"
  end
  let(:scene) do
    described_class.new.call(Sirena::Parser::Radar.new.parse(source))
  end
  let(:svg) { Sirena.render(source) }

  it "carries each ring's outline in the Scene" do
    expect(scene.grid_circles.last.polygon_points)
      .to eq("350.0,50.0 609.8076211353316,500.0 90.1923788646684,500.0")
  end

  it "serializes the Scene outline into the rendered polygon" do
    ring = svg.scan(/<polygon[^>]*class="radarGraticule"[^>]*>/).last

    expect(ring).to include(scene.grid_circles.last.polygon_points)
  end
end
