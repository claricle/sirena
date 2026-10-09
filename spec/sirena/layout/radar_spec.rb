# frozen_string_literal: true

require "spec_helper"
require "sirena/layout/radar"
require "sirena/diagram/radar"

RSpec.describe Sirena::Layout::Radar do
  subject(:graph) { described_class.new.to_graph(diagram) }

  let(:diagram) { Sirena::Diagram::Radar.new }

  it "returns the compact empty-axis canvas" do
    expect(graph).to eq(
      axes: [], curves: [], grid_circles: [], center_x: 80, center_y: 80,
      radius: 200, width: 160, height: 160, min_value: 0, max_value: 0
    )
  end

  context "with axes and a curve" do
    let(:diagram) do
      Sirena::Diagram::Radar.new.tap do |radar|
        radar.axes = [
          Sirena::Diagram::RadarAxis.new("speed", "Speed"),
          Sirena::Diagram::RadarAxis.new("quality", "Quality"),
        ]
        radar.curves = [curve]
      end
    end
    let(:curve) do
      Sirena::Diagram::RadarCurve.new("current", "Current").tap do |data|
        data.add_value("speed", 10)
        data.add_value("quality", 30)
      end
    end

    it "infers the value range and publishes final dimensions" do
      expect(graph).to include(
        min_value: 10.0, max_value: 30.0, center_x: 280, center_y: 280,
        radius: 200, width: 560, height: 560
      )
    end

    it "positions axes clockwise from the top" do
      expect(graph[:axes]).to match(
        [
          include(id: "speed", label: "Speed", angle_degrees: -90.0,
                  end_x: be_within(0.0001).of(0), end_y: -200.0,
                  label_y: -230.0, index: 0),
          include(id: "quality", label: "Quality", angle_degrees: 90.0,
                  end_x: be_within(0.0001).of(0), end_y: 200.0,
                  label_y: 230.0, index: 1),
        ],
      )
    end

    it "normalizes curve points onto their axes" do
      expect(graph[:curves]).to contain_exactly(
        include(
          id: "current",
          label: "Current",
          points: [
            include(axis_id: "speed", value: 10.0, normalized: 0.0,
                    x: be_within(0.0001).of(0), y: be_within(0.0001).of(0)),
            include(axis_id: "quality", value: 30.0, normalized: 1.0,
                    x: be_within(0.0001).of(0), y: 200.0),
          ],
        ),
      )
    end

    it "creates five evenly spaced grid circles across the range" do
      expect(graph[:grid_circles]).to eq(
        [
          { radius: 40.0, value: 14.0, fraction: 0.2 },
          { radius: 80.0, value: 18.0, fraction: 0.4 },
          { radius: 120.0, value: 22.0, fraction: 0.6 },
          { radius: 160.0, value: 26.0, fraction: 0.8 },
          { radius: 200.0, value: 30.0, fraction: 1.0 },
        ],
      )
    end
  end

  context "with configured ranges" do
    let(:diagram) do
      Sirena::Diagram::Radar.new.tap do |radar|
        radar.axes = [Sirena::Diagram::RadarAxis.new("axis")]
        radar.options = { min: -10, max: 10 }
      end
    end

    it "uses the configured minimum and maximum" do
      expect(graph.values_at(:min_value, :max_value)).to eq([-10, 10])
    end
  end

  it "repairs collapsed and decreasing configured ranges" do
    ranges = [[5, 5], [10, 2]].map { |min, max| graph_for_range(min, max) }

    expect(ranges).to eq([[5, 6], [10, 11]])
  end

  def graph_for_range(min, max)
    radar = Sirena::Diagram::Radar.new
    radar.axes = [Sirena::Diagram::RadarAxis.new("axis")]
    radar.options = { min: min, max: max }
    described_class.new.to_graph(radar).values_at(:min_value, :max_value)
  end
end
