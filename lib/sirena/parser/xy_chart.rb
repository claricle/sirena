# frozen_string_literal: true

require_relative "base"
require_relative "grammars/xy_chart"
require_relative "transforms/xy_chart"
require_relative "../diagram/xy_chart"

module Sirena
  module Parser
    # XY Chart parser for Mermaid xychart-beta diagram syntax.
    #
    # Uses Parslet grammar-based parsing to handle XY chart syntax
    # with axes and multiple datasets.
    #
    # Parses XY charts with support for:
    # - Title
    # - X-axis with categorical or numeric values
    # - Y-axis with range
    # - Multiple datasets (line, bar, or named)
    #
    # @example Parse a simple XY chart
    #   parser = XYChartParser.new
    #   source = <<~MERMAID
    #     xychart-beta
    #       title "Sales Revenue"
    #       x-axis [jan, feb, mar]
    #       y-axis 0 --> 100
    #       line [5, 10, 15]
    #   MERMAID
    #   diagram = parser.parse(source)
    class XYChartParser < Base
      # Parses XY chart diagram source into an XYChart model.
      #
      # @param source [String] the Mermaid XY chart diagram source
      # @return [Diagram::XYChart] the parsed XY chart
      # @raise [ParseError] if syntax is invalid
      def parse(source)
        grammar = Grammars::XYChart.new

        begin
          parse_tree = grammar.parse(source)
        rescue Parslet::ParseFailed => e
          raise ParseError, "Syntax error at #{e.parse_failure_cause.pos}: " \
                           "#{e.parse_failure_cause}"
        end

        # Transform parse tree to intermediate representation
        transform = Transforms::XYChart.new
        result = transform.apply(parse_tree)

        # Create the diagram model
        create_diagram(result)
      end

      private

      def create_diagram(result)
        diagram = Diagram::XYChart.new
        diagram.title = result[:title]

        # Create X-axis
        if result[:x_axis]
          diagram.x_axis = create_x_axis(result[:x_axis])
        end

        # Create Y-axis
        if result[:y_axis]
          diagram.y_axis = create_y_axis(result[:y_axis])
        end

        # Create datasets
        result[:datasets].each_with_index do |dataset_data, idx|
          dataset = Diagram::XYDataset.new(
            "dataset_#{idx}",
            dataset_data[:label],
            dataset_data[:chart_type]
          )
          dataset.values = dataset_data[:values]
          diagram.add_dataset(dataset)
        end

        diagram
      end

      def create_x_axis(axis_data)
        axis = Diagram::XYAxis.new
        axis.label = axis_data[:label]

        # Extract values and determine if categorical or numeric
        values = axis_data[:values]

        # Check if all values are numeric
        if values.all? { |v| v.is_a?(Numeric) }
          axis.type = :numeric
          axis.values = values
        else
          axis.type = :categorical
          axis.values = values.map(&:to_s)
        end

        axis
      end

      def create_y_axis(axis_data)
        axis = Diagram::XYAxis.new
        axis.label = axis_data[:label]
        axis.type = :numeric
        axis.min = axis_data[:min]
        axis.max = axis_data[:max]
        axis
      end
    end
  end
end