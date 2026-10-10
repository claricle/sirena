# frozen_string_literal: true

require "spec_helper"
require "sirena/diagram/xy_chart"
require "sirena/layout/xy_chart"

RSpec.describe Sirena::Layout::XyChart do
  subject(:scene) { described_class.new.call(diagram) }

  let(:diagram) do
    Sirena::Diagram::XyChart.new.tap do |chart|
      chart.title = "Quarterly change"
      chart.x_axis = axis("Quarter", :categorical, %w[Q1 Q2 Q3])
      chart.y_axis = axis("Change", :numeric, [], -10, 30)
      chart.datasets = [dataset("trend", :line, "red", [-10, 10, 30]),
                        dataset("volume", :bar, "blue", [0, 20, 30])]
    end
  end

  it "preserves axis labels, ranges, ordered series, and styles" do
    expect(chart_summary).to eq(expected_chart_summary)
  end

  it "converts source values into final point and bar geometry" do
    expect(geometry_summary).to eq(expected_geometry_summary)
  end

  it "lays out direct shared IR identically to the private diagram" do
    ir = Sirena::Notation::Mermaid::IRAdapters::Xychart.call(diagram)
    scenes = [diagram, ir].map { |input| described_class.new.call(input) }

    expect(scenes.map { |result| Marshal.dump(result) }.uniq.one?).to be(true)
  end

  def axis(label, type, values, minimum = nil, maximum = nil)
    Sirena::Diagram::XYAxis.new.tap do |axis|
      axis.label = label
      axis.type = type
      axis.values = values
      axis.min = minimum
      axis.max = maximum
    end
  end

  def dataset(id, type, color, values)
    Sirena::Diagram::XYDataset.new(id, id.capitalize, type).tap do |series|
      series.color = color
      series.values = values
    end
  end

  def chart_summary
    series = scene.series.map do |item|
      [item.id, item.chart_type, item.color, item.label]
    end
    [scene.title.text, scene.labels.map(&:text), series]
  end

  def expected_chart_summary
    ["Quarterly change",
     ["Quarter", "Q1", "Q2", "Q3", "Change",
      "30.0", "22.0", "14.0", "6.0", "-2.0"],
     [["trend", :line, "red", "Trend"],
      ["volume", :bar, "blue", "Volume"]]]
  end

  def geometry_summary
    line, bars = scene.series
    [line.points.map { |point| [point.x, point.y] },
     bars.bars.map { |bar| [bar.x, bar.y, bar.height] }]
  end

  def expected_geometry_summary
    [[[206.0, 420.0], [419.0, 250.0], [632.0, 80.0]],
     [[142.1, 335.0, 85.0], [355.1, 165.0, 255.0],
      [568.1, 80.0, 340.0]]]
  end
end
