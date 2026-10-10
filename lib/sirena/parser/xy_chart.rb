# frozen_string_literal: true

require_relative "base"
require_relative "grammars/xy_chart"
require_relative "builders/xy_chart"
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
    #   parser = XyChart.new
    #   source = <<~MERMAID
    #     xychart-beta
    #       title "Sales Revenue"
    #       x-axis [jan, feb, mar]
    #       y-axis 0 --> 100
    #       line [5, 10, 15]
    #   MERMAID
    #   diagram = parser.parse(source)
    class XyChart < Base
      grammar Grammars::XyChart
      builder Builders::XyChart

      private

      def create_diagram(result)
        diagram = Diagram::XyChart.new
        diagram.title = result[:title]
        assign_axes(diagram, result)
        append_datasets(diagram, result[:datasets])
        diagram
      end

      def assign_axes(diagram, result)
        diagram.x_axis = create_x_axis(result[:x_axis]) if result[:x_axis]
        diagram.y_axis = create_y_axis(result[:y_axis]) if result[:y_axis]
      end

      def append_datasets(diagram, datasets)
        datasets.each_with_index do |data, index|
          diagram.add_dataset(build_dataset(data, index))
        end
      end

      def build_dataset(data, index)
        dataset = Diagram::XYDataset.new(
          "dataset_#{index}", data[:label], data[:chart_type]
        )
        dataset.values = data[:values]
        dataset
      end

      def create_x_axis(axis_data)
        axis = Diagram::XYAxis.new
        axis.label = axis_data[:label]
        assign_x_values(axis, axis_data[:values])
        axis
      end

      def assign_x_values(axis, values)
        if values.all?(Numeric)
          axis.type = :numeric
          axis.values = values
        else
          axis.type = :categorical
          axis.values = values.map(&:to_s)
        end
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
