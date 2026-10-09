# frozen_string_literal: true

require_relative "base"
require_relative "grammars/radar"
require_relative "builders/radar"
require_relative "../diagram/radar"

module Sirena
  module Parser
    # Radar chart parser for Mermaid radar-beta diagram syntax.
    #
    # Uses Parslet grammar-based parsing to handle radar chart syntax
    # with axes and multiple data curves.
    #
    # Parses radar charts with support for:
    # - Title and accessibility metadata
    # - Axis definitions with labels
    # - Multiple data curves/datasets
    # - Configuration options (ticks, legend, graticule, min/max)
    #
    # @example Parse a simple radar chart
    #   parser = Radar.new
    #   source = <<~MERMAID
    #     radar-beta
    #       title Skills Assessment
    #       axis A, B, C
    #       curve mycurve{1, 2, 3}
    #   MERMAID
    #   diagram = parser.parse(source)
    class Radar < Base
      grammar Grammars::Radar
      builder Builders::Radar

      private

      def create_diagram(result)
        diagram = Diagram::Radar.new
        diagram.title = result[:title]
        diagram.acc_title = result[:acc_title]
        diagram.acc_descr = result[:acc_descr]
        diagram.options = result[:options]

        # Create axes
        result[:axes].each do |axis_data|
          axis = Diagram::RadarAxis.new(
            axis_data[:id],
            axis_data[:label],
          )
          diagram.axes << axis
        end

        # Create curves
        result[:curves].each do |curve_data|
          curve = Diagram::RadarCurve.new(
            curve_data[:id],
            curve_data[:label],
          )

          # Add values - handle both positional and named formats
          values = Array(curve_data[:values])

          if values.first.is_a?(Hash) && values.first[:axis]
            # Named format: { axis: "A", value: 1.0 }
            values.each do |val|
              curve.add_value(val[:axis], val[:value])
            end
          else
            # Positional format: [1.0, 2.0, 3.0]
            values.each_with_index do |val, idx|
              next unless diagram.axes[idx]

              axis_id = diagram.axes[idx].id
              curve.add_value(axis_id, val)
            end
          end

          diagram.curves << curve
        end

        diagram
      end
    end
  end
end
