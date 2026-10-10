# frozen_string_literal: true

require "spec_helper"
require "sirena/diagram/xy_chart"

RSpec.describe Sirena::Diagram::XyChart do
  def categorical_axis(values = [])
    Sirena::Diagram::XYAxis.new.tap do |axis|
      axis.type = :categorical
      axis.values = values
    end
  end

  describe Sirena::Diagram::XYAxis do
    it "uses default numeric bounds independently" do
      lower = described_class.new.tap { |axis| axis.min = 5 }
      upper = described_class.new.tap { |axis| axis.max = 80 }

      expect([lower.range, upper.range]).to eq([[5, 100], [0, 80]])
    end

    it "maps categorical values to indexes including an empty axis" do
      filled = categorical_axis(%w[a b c])
      empty = categorical_axis

      expect([filled.range, empty.range]).to eq([[0, 2], [0, -1]])
    end

    it "reports numeric and categorical modes as opposites" do
      numeric = described_class.new
      categorical = categorical_axis

      expect([numeric.numeric?, numeric.categorical?, categorical.numeric?,
              categorical.categorical?]).to eq([true, false, false, true])
    end
  end

  describe Sirena::Diagram::XYDataset do
    it "defaults the label to its id and preserves explicit chart type" do
      dataset = described_class.new("sales", nil, :scatter)

      expect([dataset.label, dataset.chart_type, dataset.values])
        .to eq(["sales", :scatter, []])
    end
  end
end
