# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/xy_chart"

RSpec.describe Sirena::Parser::XyChart, :aggregate_failures do
  let(:parser) { described_class.new }

  let(:full_chart_source) do
    <<~MERMAID
      xychart-beta
          title "Sales Revenue"
          x-axis [jan, feb, mar, apr, may, jun, jul, aug, sep, oct, nov, dec]
          y-axis "Revenue (in $)" 4000 --> 11000
          bar [5000, 6000, 7500, 8200, 9500, 10500, 11000, 10200, 9200, 8500, 7000, 6000]
          line [5000, 6000, 7500, 8200, 9500, 10500, 11000, 10200, 9200, 8500, 7000, 6000]
    MERMAID
  end

  def parse_chart(*lines)
    source = ["xychart-beta", *lines].join("\n")
    parser.parse("#{source}\n")
  end

  def datasets_from(statement)
    parse_chart(
      "x-axis [jan, feb, mar]", "y-axis 0 --> 100", statement
    ).datasets
  end

  def titled_axes_lines
    ['title "Sales Revenue"', "x-axis [jan, feb, mar]", "y-axis 0 --> 100"]
  end

  def labelled_y_axis_lines
    ["x-axis [jan, feb, mar]", 'y-axis "Revenue (in $)" 4000 --> 11000']
  end

  def full_chart_summary(diagram)
    [
      diagram.title, diagram.x_axis.values.size,
      diagram.y_axis.min, diagram.y_axis.max,
      diagram.datasets.map(&:chart_type), diagram.datasets.first.values.size
    ]
  end

  describe "#parse" do
    context "with simple XY chart" do
      it "parses xychart-beta keyword" do
        diagram = parse_chart

        expect(diagram).to be_a(Sirena::Diagram::XyChart)
      end

      it "reads a body of only comments and blank lines as empty" do
        diagram = parser.parse("xychart-beta\n%% only a comment\n\n")

        expect([diagram.title, diagram.datasets]).to eq([nil, []])
      end

      it "parses chart with title and axes" do
        diagram = parse_chart(*titled_axes_lines)

        expect(diagram.title).to eq("Sales Revenue")
        expect(diagram.x_axis).not_to be_nil
        expect(diagram.y_axis).not_to be_nil
      end
    end

    context "with X-axis" do
      it "parses categorical X-axis" do
        diagram = parse_chart("x-axis [jan, feb, mar, apr]", "y-axis 0 --> 100")

        expect(diagram.x_axis.type).to eq(:categorical)
        expect(diagram.x_axis.values).to eq(["jan", "feb", "mar", "apr"])
      end

      it "parses X-axis with label" do
        diagram = parse_chart(
          'x-axis "Month" [jan, feb, mar]', "y-axis 0 --> 100"
        )

        expect(diagram.x_axis.label).to eq("Month")
        expect(diagram.x_axis.values).to eq(["jan", "feb", "mar"])
      end

      it "parses numeric X-axis" do
        diagram = parse_chart("x-axis [1, 2, 3, 4, 5]", "y-axis 0 --> 100")

        expect(diagram.x_axis.type).to eq(:numeric)
        expect(diagram.x_axis.values).to eq([1, 2, 3, 4, 5])
      end
    end

    context "with Y-axis" do
      it "parses Y-axis with range" do
        diagram = parse_chart("x-axis [jan, feb, mar]", "y-axis 0 --> 100")

        expect(diagram.y_axis.min).to eq(0)
        expect(diagram.y_axis.max).to eq(100)
      end

      it "parses Y-axis with label and range" do
        diagram = parse_chart(*labelled_y_axis_lines)

        expect(diagram.y_axis.label).to eq("Revenue (in $)")
        expect(diagram.y_axis.min).to eq(4000)
        expect(diagram.y_axis.max).to eq(11000)
      end
    end

    context "with datasets" do
      it "parses line dataset" do
        datasets = datasets_from("line [10, 20, 30]")

        expect(datasets).to contain_exactly(
          have_attributes(chart_type: :line, values: [10, 20, 30]),
        )
      end

      it "parses bar dataset" do
        datasets = datasets_from("bar [15, 25, 35]")

        expect(datasets).to contain_exactly(
          have_attributes(chart_type: :bar, values: [15, 25, 35]),
        )
      end

      it "parses named dataset" do
        datasets = datasets_from('dataset "Series A" [10, 20, 30]')

        expect(datasets).to contain_exactly(
          have_attributes(label: "Series A", values: [10, 20, 30]),
        )
      end

      it "parses multiple datasets" do
        diagram = parse_chart(
          "x-axis [jan, feb, mar]", "y-axis 0 --> 100",
          "line [10, 20, 30]", "bar [15, 25, 35]"
        )
        expect(diagram.datasets.map(&:chart_type)).to eq(%i[line bar])
      end
    end

    context "with complex example" do
      it "parses full XY chart from fixture" do
        expected = ["Sales Revenue", 12, 4000, 11_000, %i[bar line], 12]
        actual = full_chart_summary(parser.parse(full_chart_source))

        expect(actual).to eq(expected)
      end
    end
  end
end
