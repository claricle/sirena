# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/xy_chart"
require "sirena/layout/xy_chart"
require "sirena/renderer/xy_chart"

RSpec.describe Sirena::Renderer::XyChart do
  subject(:renderer) { described_class.new }

  let(:source) do
    <<~MERMAID
      xychart-beta
        title "Sales Revenue"
        x-axis "Month" [jan, feb, mar]
        y-axis "Revenue" 0 --> 100
        line [10, 20, 30]
        bar [15, 25, 35]
    MERMAID
  end
  let(:diagram) { Sirena::Parser::XyChart.new.parse(source) }
  let(:scene) { Sirena::Layout::XyChart.new.call(diagram) }

  it "returns typed final chart geometry" do
    expect(scene).to be_a(Sirena::Layout::XyChart::Scene)
    expect(scene.series).to all(be_a(Sirena::Layout::XyChart::Series))
    expect(scene.lines).to all(be_a(Sirena::Layout::XyChart::Line))
    expect(scene.view_box).to eq("0 0 800 500")
  end

  it "positions line points and bars in canvas coordinates" do
    line, bar = scene.series

    expect(line.points.map(&:x)).to all(be >= Sirena::Layout::XyChart::MARGIN_LEFT)
    expect(line.polyline).to include("#{line.points.first.x},#{line.points.first.y}")
    expect(bar.bars.map(&:x)).to all(be >= Sirena::Layout::XyChart::MARGIN_LEFT)
  end

  it "renders axes, both series, labels, and legends" do
    svg = renderer.render(scene)
    texts = svg.children.grep(Sirena::Svg::Text).map do |text|
      Array(text.content).join
    end

    expect(svg.children.grep(Sirena::Svg::Polyline).length).to eq(1)
    expect(svg.children.grep(Sirena::Svg::Circle).length).to eq(3)
    expect(svg.children.grep(Sirena::Svg::Rect).length).to be >= 5
    expect(texts).to include("Sales Revenue", "Month", "Revenue", "Line", "Bar")
  end

  it "uses Scene canvas dimensions verbatim" do
    svg = renderer.render(scene)

    expect([svg.width, svg.height, svg.view_box])
      .to eq([scene.width, scene.height, scene.view_box])
  end
end
