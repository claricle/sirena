# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/xychart"

RSpec.describe Sirena::Notation::Mermaid::IRAdapters::XyChart do
  subject(:ir) { described_class.call(diagram) }

  let(:diagram) do
    dataset = Sirena::Diagram::XYDataset.new(nil)
    dataset.chart_type = nil
    Sirena::Diagram::XyChart.new.tap do |chart|
      chart.id = "horizontal_axis"
      chart.datasets = [dataset]
    end
  end

  it "uses default axes and omits absent series properties" do
    horizontal, vertical, series = ir.items

    expect([horizontal.id, placement_values(horizontal),
            vertical.label, placement_values(vertical),
            series.id, placement_values(series)])
      .to eq(expected_items)
  end

  def placement_values(item)
    item.placements.to_h do |placement|
      [placement.dimension, placement.value.value]
    end
  end

  def expected_items
    ["horizontal_axis_2",
     { "axis_direction" => "horizontal", "axis_kind" => "numeric",
       "minimum" => 0.0, "maximum" => 10.0 },
     nil,
     { "axis_direction" => "vertical", "axis_kind" => "numeric",
       "minimum" => 0.0, "maximum" => 100.0 },
     "series_0", { "series_order" => 0.0 }]
  end
end
