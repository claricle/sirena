# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/xy_chart"

RSpec.describe Sirena::Parser::XYChartParser do
  let(:parser) { described_class.new }

  describe "#parse" do
    context "with simple XY chart" do
      it "parses xychart-beta keyword" do
        source = <<~MERMAID
          xychart-beta
        MERMAID

        diagram = parser.parse(source)
        expect(diagram).to be_a(Sirena::Diagram::XYChart)
      end

      it "parses chart with title and axes" do
        source = <<~MERMAID
          xychart-beta
              title "Sales Revenue"
              x-axis [jan, feb, mar]
              y-axis 0 --> 100
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.title).to eq("Sales Revenue")
        expect(diagram.x_axis).not_to be_nil
        expect(diagram.y_axis).not_to be_nil
      end
    end

    context "with X-axis" do
      it "parses categorical X-axis" do
        source = <<~MERMAID
          xychart-beta
              x-axis [jan, feb, mar, apr]
              y-axis 0 --> 100
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.x_axis.type).to eq(:categorical)
        expect(diagram.x_axis.values).to eq(["jan", "feb", "mar", "apr"])
      end

      it "parses X-axis with label" do
        source = <<~MERMAID
          xychart-beta
              x-axis "Month" [jan, feb, mar]
              y-axis 0 --> 100
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.x_axis.label).to eq("Month")
        expect(diagram.x_axis.values).to eq(["jan", "feb", "mar"])
      end

      it "parses numeric X-axis" do
        source = <<~MERMAID
          xychart-beta
              x-axis [1, 2, 3, 4, 5]
              y-axis 0 --> 100
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.x_axis.type).to eq(:numeric)
        expect(diagram.x_axis.values).to eq([1, 2, 3, 4, 5])
      end
    end

    context "with Y-axis" do
      it "parses Y-axis with range" do
        source = <<~MERMAID
          xychart-beta
              x-axis [jan, feb, mar]
              y-axis 0 --> 100
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.y_axis.min).to eq(0)
        expect(diagram.y_axis.max).to eq(100)
      end

      it "parses Y-axis with label and range" do
        source = <<~MERMAID
          xychart-beta
              x-axis [jan, feb, mar]
              y-axis "Revenue (in $)" 4000 --> 11000
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.y_axis.label).to eq("Revenue (in $)")
        expect(diagram.y_axis.min).to eq(4000)
        expect(diagram.y_axis.max).to eq(11000)
      end
    end

    context "with datasets" do
      it "parses line dataset" do
        source = <<~MERMAID
          xychart-beta
              x-axis [jan, feb, mar]
              y-axis 0 --> 100
              line [10, 20, 30]
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.datasets.size).to eq(1)
        expect(diagram.datasets.first.chart_type).to eq(:line)
        expect(diagram.datasets.first.values).to eq([10, 20, 30])
      end

      it "parses bar dataset" do
        source = <<~MERMAID
          xychart-beta
              x-axis [jan, feb, mar]
              y-axis 0 --> 100
              bar [15, 25, 35]
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.datasets.size).to eq(1)
        expect(diagram.datasets.first.chart_type).to eq(:bar)
        expect(diagram.datasets.first.values).to eq([15, 25, 35])
      end

      it "parses named dataset" do
        source = <<~MERMAID
          xychart-beta
              x-axis [jan, feb, mar]
              y-axis 0 --> 100
              dataset "Series A" [10, 20, 30]
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.datasets.size).to eq(1)
        expect(diagram.datasets.first.label).to eq("Series A")
        expect(diagram.datasets.first.values).to eq([10, 20, 30])
      end

      it "parses multiple datasets" do
        source = <<~MERMAID
          xychart-beta
              x-axis [jan, feb, mar]
              y-axis 0 --> 100
              line [10, 20, 30]
              bar [15, 25, 35]
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.datasets.size).to eq(2)
        expect(diagram.datasets[0].chart_type).to eq(:line)
        expect(diagram.datasets[1].chart_type).to eq(:bar)
      end
    end

    context "with complex example" do
      it "parses full XY chart from fixture" do
        source = <<~MERMAID
          xychart-beta
              title "Sales Revenue"
              x-axis [jan, feb, mar, apr, may, jun, jul, aug, sep, oct, nov, dec]
              y-axis "Revenue (in $)" 4000 --> 11000
              bar [5000, 6000, 7500, 8200, 9500, 10500, 11000, 10200, 9200, 8500, 7000, 6000]
              line [5000, 6000, 7500, 8200, 9500, 10500, 11000, 10200, 9200, 8500, 7000, 6000]
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.title).to eq("Sales Revenue")
        expect(diagram.x_axis.values.size).to eq(12)
        expect(diagram.y_axis.min).to eq(4000)
        expect(diagram.y_axis.max).to eq(11000)
        expect(diagram.datasets.size).to eq(2)
        expect(diagram.datasets[0].chart_type).to eq(:bar)
        expect(diagram.datasets[1].chart_type).to eq(:line)
        expect(diagram.datasets[0].values.size).to eq(12)
      end
    end
  end
end