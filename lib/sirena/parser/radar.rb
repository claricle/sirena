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
        assign_metadata(diagram, result)
        append_axes(diagram, result[:axes])
        append_curves(diagram, result[:curves])
        diagram
      end

      def assign_metadata(diagram, result)
        diagram.title = result[:title]
        diagram.acc_title = result[:acc_title]
        diagram.acc_descr = result[:acc_descr]
        diagram.options = result[:options]
      end

      def append_axes(diagram, axes)
        axes.each do |data|
          diagram.axes << Diagram::RadarAxis.new(data[:id], data[:label])
        end
      end

      def append_curves(diagram, curves)
        curves.each do |data|
          diagram.curves << build_curve(data, diagram.axes)
        end
      end

      def build_curve(data, axes)
        curve = Diagram::RadarCurve.new(data[:id], data[:label])
        assign_curve_values(curve, Array(data[:values]), axes)
        curve
      end

      def assign_curve_values(curve, values, axes)
        return assign_named_values(curve, values) if named_values?(values)

        assign_positional_values(curve, values, axes)
      end

      def named_values?(values)
        values.first.is_a?(Hash) && values.first[:axis]
      end

      def assign_named_values(curve, values)
        values.each { |value| curve.add_value(value[:axis], value[:value]) }
      end

      def assign_positional_values(curve, values, axes)
        values.each_with_index do |value, index|
          next unless axes[index]

          curve.add_value(axes[index].id, value)
        end
      end
    end
  end
end
