# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Radar, "#call" do
  subject(:scene) { described_class.new.call(diagram) }

  let(:diagram) { Sirena::Parser::Radar.new.parse(source) }
  let(:source) do
    "radar-beta\n  axis a, b, c\n  curve c1{1, 2, 3}\n  ticks 3\n"
  end

  it "draws as many rings as the ticks option asks for" do
    expect(scene.grid_circles.map(&:radius)).to eq([100.0, 200.0, 300.0])
  end

  it "keeps a closed Bezier path with mermaid's 0.17 tension" do
    expect(scene.curves.first.path_data)
      .to start_with("M350.0,250.0 C423.6121")
  end

  it "puts the first legend swatch at three quarters of the frame" do
    label = scene.legend.first.label

    expect([label.x, label.y]).to eq([628.5, 87.5])
  end

  it "records a polygon graticule" do
    polygon = Sirena::Parser::Radar.new.parse("#{source}  graticule polygon\n")

    expect(described_class.new.call(polygon).grid_shape).to eq("polygon")
  end
end
