# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::XyChart do
  subject(:layout) { described_class.new }

  def categorical_axis(values = ["Q1"])
    Sirena::Diagram::XYAxis.new.tap do |axis|
      axis.label = "Quarter"
      axis.type = :categorical
      axis.values = values
    end
  end

  def numeric_axis
    Sirena::Diagram::XYAxis.new.tap do |axis|
      axis.label = "Change"
      axis.type = :numeric
      axis.min = 0
      axis.max = 20
    end
  end

  def themed_scene
    diagram = Sirena::Diagram::XyChart.new
    diagram.title = "Quarterly change"
    diagram.x_axis = categorical_axis
    diagram.y_axis = numeric_axis
    layout.call(diagram, theme: Sirena::Theme.new)
  end

  def overflow_points
    diagram = Sirena::Diagram::XyChart.new
    diagram.x_axis = categorical_axis(["Only"])
    diagram.y_axis = numeric_axis
    diagram.datasets = [overflow_dataset]
    layout.call(diagram).series.first.points
  end

  def overflow_dataset
    Sirena::Diagram::XYDataset.new("trend", "Trend", :line).tap do |series|
      series.values = [10, 20]
    end
  end

  def scene_font_sizes(scene)
    [scene.title.font_size, scene.labels.first.font_size,
     scene.labels.fetch(1).font_size]
  end

  def fallback_font_sizes
    fallback = Sirena::Theme::Registry.get(:default).typography
    [fallback.font_size_large, fallback.font_size_normal,
     fallback.font_size_small]
  end

  it "supplies both axes when shared IR omits them" do
    document = Sirena::IR::Prepositioned.new(id: "chart", role: "xy_chart")
    scene = layout.call(document)

    expect([scene.labels.map(&:text),
            scene.lines.count { |line| line.kind == "grid" }])
      .to eq([%w[100 80 60 40 20], 5])
  end

  it "uses default font sizes when an injected theme has no typography" do
    expect(scene_font_sizes(themed_scene)).to eq(fallback_font_sizes)
  end

  it "places values beyond the categorical axis at its origin" do
    expect(overflow_points.map(&:x)).to eq([420.0, 100.0])
  end
end
