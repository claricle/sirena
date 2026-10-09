# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Diagram do
  describe Sirena::Diagram::XyChart do
    subject(:chart) { described_class.new }

    it "starts with no datasets" do
      expect(chart.datasets).to be_empty
    end

    it "starts with no options" do
      expect(chart.options).to be_empty
    end

    it "adds a dataset" do
      dataset = Sirena::Diagram::XYDataset.new("sales")

      expect { chart.add_dataset(dataset) }.to change(chart.datasets, :count).by(1)
    end

    it "identifies itself as an xy chart" do
      expect(chart.diagram_type).to eq(:xychart)
    end

    it "is valid without configuration" do
      expect(chart).to be_valid
    end
  end

  describe Sirena::Diagram::XYAxis do
    subject(:axis) { described_class.new }

    it "defaults to numeric" do
      expect(axis).to be_numeric
    end

    it "does not default to categorical" do
      expect(axis).not_to be_categorical
    end

    it "uses the default numeric range" do
      expect(axis.range).to eq([0, 100])
    end

    it "uses a custom numeric range" do
      axis.min = -10
      axis.max = 25

      expect(axis.range).to eq([-10, 25])
    end

    it "reports a categorical axis" do
      axis.type = :categorical

      expect(axis).to be_categorical
    end

    it "does not report a categorical axis as numeric" do
      axis.type = :categorical

      expect(axis).not_to be_numeric
    end

    it "derives the categorical range from its values" do
      axis.type = :categorical
      axis.values = %w[first second third]

      expect(axis.range).to eq([0, 2])
    end

    it "uses an empty categorical range when no values exist" do
      axis.type = :categorical

      expect(axis.range).to eq([0, -1])
    end
  end

  describe Sirena::Diagram::XYDataset do
    it "uses its id as the default label" do
      expect(described_class.new("sales").label).to eq("sales")
    end

    it "defaults to a line chart" do
      expect(described_class.new("sales").chart_type).to eq(:line)
    end

    it "accepts a custom label" do
      expect(described_class.new("sales", "Quarterly").label).to eq("Quarterly")
    end

    it "accepts a custom chart type" do
      dataset = described_class.new("sales", "Quarterly", :bar)

      expect(dataset.chart_type).to eq(:bar)
    end
  end
end
