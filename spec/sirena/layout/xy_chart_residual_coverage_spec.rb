# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::XyChart do
  subject(:layout) { described_class.new }

  it "supplies both axes when shared IR omits them" do
    document = Sirena::IR::Prepositioned.new(id: "chart", role: "xy_chart")
    scene = layout.call(document)

    expect([scene.labels.map(&:text),
            scene.lines.count { |line| line.kind == "grid" }])
      .to eq([%w[100 80 60 40 20], 5])
  end

  it "uses default font sizes when an injected theme has no typography" do
    diagram = Sirena::Diagram::XyChart.new.tap do |chart|
      chart.title = "Quarterly change"
      chart.x_axis = Sirena::Diagram::XYAxis.new.tap do |axis|
        axis.label = "Quarter"
        axis.type = :categorical
        axis.values = ["Q1"]
      end
      chart.y_axis = Sirena::Diagram::XYAxis.new.tap do |axis|
        axis.label = "Change"
        axis.type = :numeric
        axis.min = 0
        axis.max = 20
      end
    end
    scene = layout.call(diagram, theme: Sirena::Theme.new)
    fallback = Sirena::Theme::Registry.get(:default).typography

    expect([scene.title.font_size, scene.labels.first.font_size,
            scene.labels.fetch(1).font_size])
      .to eq([fallback.font_size_large, fallback.font_size_normal,
              fallback.font_size_small])
  end

  it "places values beyond the categorical axis at its origin" do
    diagram = Sirena::Diagram::XyChart.new
    diagram.x_axis = Sirena::Diagram::XYAxis.new.tap do |axis|
      axis.type = :categorical
      axis.values = ["Only"]
    end
    diagram.y_axis = Sirena::Diagram::XYAxis.new.tap do |axis|
      axis.type = :numeric
      axis.min = 0
      axis.max = 20
    end
    diagram.datasets = [
      Sirena::Diagram::XYDataset.new("trend", "Trend", :line).tap do |series|
        series.values = [10, 20]
      end,
    ]

    expect(layout.call(diagram).series.first.points.map(&:x)).to eq([420.0, 100.0])
  end
end
