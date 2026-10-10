# frozen_string_literal: true

require "spec_helper"
require "sirena/diagram/quadrant"
require "sirena/diagram/xy_chart"
require "sirena/notation/mermaid/ir_adapters/quadrant"
require "sirena/notation/mermaid/ir_adapters/xychart"

module Sirena
  module Notation
    module Mermaid
      module IRAdapters
        # Groups the coordinate-chart adapters for their shared contract spec.
        module CoordinateCharts; end
      end
    end
  end
end

RSpec.describe Sirena::Notation::Mermaid::IRAdapters::CoordinateCharts do
  def values(item)
    item.placements.to_h do |placement|
      [placement.dimension, placement.value.value]
    end
  end

  describe Sirena::Notation::Mermaid::IRAdapters::Quadrant do
    subject(:ir) { described_class.call(diagram) }

    let(:diagram) do
      Sirena::Diagram::Quadrant.new(
        id: "coordinate_frame", title: "Portfolio",
        x_axis_left: "safe", quadrant_1_label: "invest",
        points: [Sirena::Diagram::QuadrantPoint.new(
          label: "growth", x: 0.75, y: 0.8, radius: 9,
          color: "red", stroke_color: "navy", stroke_width: 3
        )]
      )
    end

    it "preserves ordered labels, point values, styles, and containment" do
      expect(quadrant_summary).to eq(expected_quadrant_summary)
    end

    it "keeps axis and region labels in source order" do
      labels = ir.items.select { |item| item.role.end_with?("_label") }

      expect(labels.map { |item| [item.label, values(item).values.first] })
        .to eq([["safe", "x_min"], [nil, "x_max"], [nil, "y_min"],
                [nil, "y_max"], ["invest", 1.0], [nil, 2.0],
                [nil, 3.0], [nil, 4.0]])
    end
  end

  describe Sirena::Notation::Mermaid::IRAdapters::Xychart do
    subject(:ir) { described_class.call(diagram) }

    let(:diagram) do
      Sirena::Diagram::XyChart.new.tap do |chart|
        chart.id = "horizontal_axis"
        chart.title = "Revenue"
        chart.x_axis = axis("Month", :categorical, %w[jan feb mar])
        chart.y_axis = axis("USD", :numeric, [], -10, 30)
        chart.datasets = [dataset("line", :line, "red", [1, 2]),
                          dataset("bars", :bar, "blue", [3, 4])]
      end
    end

    it "preserves ranges, categories, series order, values, and styles" do
      expect(xy_ir_summary).to eq(expected_xy_ir)
    end
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

  def quadrant_summary
    point = item_with_role("point")
    frame = item_with_role("coordinate_frame")
    series = item_with_role("point_series")
    [ir.valid?, ir.id, ir.label, frame.id, series.parent_id,
     point.parent_id, point.label, values(point)]
  end

  def expected_quadrant_summary
    [true, "coordinate_frame", "Portfolio", "coordinate_frame_2",
     "coordinate_frame_2", "point_series", "growth",
     { "x_value" => 0.75, "y_value" => 0.8,
       "marker_size" => 9.0, "stroke_width" => 3.0,
       "fill_color" => "red", "stroke_color" => "navy" }]
  end

  def xy_ir_summary
    [ir.valid?, ir.id, axis_values, identified_values("data_series"),
     parented_values("sample")]
  end

  def item_with_role(role)
    ir.items.find { |item| item.role == role }
  end

  def items_with_role(role)
    ir.items.select { |item| item.role == role }
  end

  def axis_values
    ir.items.select { |item| item.role.end_with?("_axis") }.map do |item|
      values(item)
    end
  end

  def identified_values(role)
    items_with_role(role).map { |item| [item.id, values(item)] }
  end

  def parented_values(role)
    items_with_role(role).map { |item| [item.parent_id, values(item)] }
  end

  def expected_xy_ir
    [true, "horizontal_axis",
     [{ "axis_direction" => "horizontal", "axis_kind" => "categorical",
        "minimum" => 0.0, "maximum" => 2.0 },
      { "axis_direction" => "vertical", "axis_kind" => "numeric",
        "minimum" => -10.0, "maximum" => 30.0 }],
     [["line", { "series_order" => 0.0,
                 "chart_kind" => "line", "series_color" => "red" }],
      ["bars", { "series_order" => 1.0,
                 "chart_kind" => "bar", "series_color" => "blue" }]],
     [["line", { "value" => 1.0 }], ["line", { "value" => 2.0 }],
      ["bars", { "value" => 3.0 }], ["bars", { "value" => 4.0 }]]]
  end
end
