# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::XyChart, "#render" do
  let(:source) do
    "xychart-beta\n  x-axis [a, b]\n  y-axis 0 --> 10\n  line [1, 2]\n"
  end
  let(:scene) do
    diagram = Sirena::Parser::XyChart.new.parse(source)
    Sirena::Layout::XyChart.new.call(diagram)
  end
  let(:xml) { described_class.new.render(scene).to_xml }

  it "draws the polyline of a line series" do
    expect(xml).to include("<polyline")
  end

  it "draws nothing for a line series without points" do
    scene.series.first.points = []

    expect(xml).not_to include("<polyline")
  end
end
