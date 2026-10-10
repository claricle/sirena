# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::XyChart do
  subject(:layout) { described_class.new }

  def empty_scene
    layout.call(Sirena::Diagram::XyChart.new)
  end

  def collapsed_bar_scene
    diagram = Sirena::Diagram::XyChart.new
    diagram.x_axis = categorical_axis([])
    diagram.y_axis = numeric_axis(5, 5)
    diagram.datasets = [bar_dataset([5])]
    layout.call(diagram)
  end

  def categorical_axis(values)
    Sirena::Diagram::XYAxis.new.tap do |axis|
      axis.type = :categorical
      axis.values = values
    end
  end

  def numeric_axis(minimum, maximum)
    Sirena::Diagram::XYAxis.new.tap do |axis|
      axis.min = minimum
      axis.max = maximum
    end
  end

  def bar_dataset(values)
    Sirena::Diagram::XYDataset.new("bars", nil, :bar).tap do |dataset|
      dataset.values = values
    end
  end

  it "uses untitled numeric defaults for an empty chart" do
    scene = empty_scene
    expect([scene.title, scene.series, scene.legends,
            scene.lines.count { |line| line.kind == "grid" },
            scene.labels.map(&:text)])
      .to eq([nil, [], [], 5, %w[100.0 80.0 60.0 40.0 20.0]])
  end

  it "falls back from empty categories and flattens a collapsed range" do
    scene = collapsed_bar_scene
    bar = scene.series.fetch(0).bars.fetch(0)
    expect([bar.width, bar.y, bar.height,
            scene.lines.count { |line| line.kind == "grid" }])
      .to eq([20.0, 420.0, 0.0, 5])
  end
end
