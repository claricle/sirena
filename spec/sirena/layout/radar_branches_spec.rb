# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Radar do
  subject(:layout) { described_class.new }

  def four_axis_scene
    diagram = Sirena::Diagram::Radar.new
    diagram.axes = %w[top right bottom left].map do |id|
      Sirena::Diagram::RadarAxis.new(id)
    end
    layout.call(diagram)
  end

  def missing_measurement_scene
    diagram = Sirena::Diagram::Radar.new
    diagram.axes = [Sirena::Diagram::RadarAxis.new("unused")]
    diagram.curves = [Sirena::Diagram::RadarCurve.new("empty")]
    diagram.options = { show_legend: false }
    layout.call(diagram)
  end

  it "selects anchors and baselines for all four compass directions" do
    labels = four_axis_scene.axes.map(&:label)
    expect([labels.map(&:text_anchor), labels.map(&:dominant_baseline)])
      .to eq([%w[end middle start middle],
              %w[middle auto middle hanging]])
  end

  it "defaults absent measurements to zero and honors a hidden legend" do
    scene = missing_measurement_scene
    point = scene.curves.fetch(0).points.fetch(0)
    expect([point.value, point.normalized, point.x, point.y, scene.legend])
      .to eq([0.0, 0.0, 280.0, 280.0, []])
  end
end
