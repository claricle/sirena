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

  def scene_summary
    [scene.class, scene.series.map(&:class).uniq,
     scene.lines.map(&:class).uniq, scene.view_box]
  end

  def position_summary
    line, bar = scene.series
    minimum = Sirena::Layout::XyChart::MARGIN_LEFT
    first_point = "#{line.points.first.x},#{line.points.first.y}"
    [line.points.map(&:x).min >= minimum,
     bar.bars.map(&:x).min >= minimum,
     line.polyline.include?(first_point)]
  end

  def render_summary
    svg = renderer.render(scene)
    texts = svg.children.grep(Sirena::Svg::Text).map do |text|
      Array(text.content).join
    end
    counts = [Sirena::Svg::Polyline, Sirena::Svg::Circle, Sirena::Svg::Rect]
      .map { |type| svg.children.grep(type).length }
    labels = ["Sales Revenue", "Month", "Revenue", "Line", "Bar"]
    [counts[0], counts[1], counts[2] >= 5,
     labels.all? { |label| texts.include?(label) }]
  end

  it "returns typed final chart geometry" do
    expected = [Sirena::Layout::XyChart::Scene,
                [Sirena::Layout::XyChart::Series],
                [Sirena::Layout::XyChart::Line], "0 0 800 500"]
    expect(scene_summary).to eq(expected)
  end

  it "positions line points and bars in canvas coordinates" do
    expect(position_summary).to eq([true, true, true])
  end

  it "renders axes, both series, labels, and legends" do
    expect(render_summary).to eq([1, 3, true, true])
  end

  it "uses Scene canvas dimensions verbatim" do
    svg = renderer.render(scene)

    expect([svg.width, svg.height, svg.view_box])
      .to eq([scene.width, scene.height, scene.view_box])
  end
end
