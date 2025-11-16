# frozen_string_literal: true

require 'lutaml/model'
require_relative 'base'

module Sirena
  module Diagram
    # Represents a data point in a quadrant chart.
    #
    # A point has a label, normalized x/y coordinates (0-1 range),
    # and optional styling parameters.
    class QuadrantPoint < Lutaml::Model::Serializable
      # Label/name for this point
      attribute :label, :string

      # X coordinate (normalized 0-1)
      attribute :x, :float

      # Y coordinate (normalized 0-1)
      attribute :y, :float

      # Optional radius for the point
      attribute :radius, :float

      # Optional fill color
      attribute :color, :string

      # Optional stroke color
      attribute :stroke_color, :string

      # Optional stroke width
      attribute :stroke_width, :float

      # Validates the point has required attributes.
      #
      # @return [Boolean] true if point is valid
      def valid?
        !label.nil? && !label.empty? &&
          !x.nil? && !y.nil? &&
          x >= 0.0 && x <= 1.0 &&
          y >= 0.0 && y <= 1.0
      end

      # Determine which quadrant this point is in (1-4).
      #
      # Quadrants are numbered:
      # - Quadrant 1: top-right (x >= 0.5, y >= 0.5)
      # - Quadrant 2: top-left (x < 0.5, y >= 0.5)
      # - Quadrant 3: bottom-left (x < 0.5, y < 0.5)
      # - Quadrant 4: bottom-right (x >= 0.5, y < 0.5)
      #
      # @return [Integer] quadrant number (1-4)
      def quadrant
        if x >= 0.5 && y >= 0.5
          1
        elsif x < 0.5 && y >= 0.5
          2
        elsif x < 0.5 && y < 0.5
          3
        else
          4
        end
      end
    end

    # Quadrant chart diagram model.
    #
    # Represents a 2x2 quadrant chart for visualizing data points
    # in a two-dimensional space. Useful for categorizing items
    # based on two independent variables.
    #
    # @example Creating a simple quadrant chart
    #   chart = QuadrantChart.new
    #   chart.title = 'Product Analysis'
    #   chart.x_axis_left = 'Low Cost'
    #   chart.x_axis_right = 'High Cost'
    #   chart.y_axis_bottom = 'Low Value'
    #   chart.y_axis_top = 'High Value'
    #   chart.quadrant_1_label = 'Invest'
    #   chart.points << QuadrantPoint.new(label: 'Product A', x: 0.3, y: 0.7)
    class QuadrantChart < Base
      # X-axis label for the left side
      attribute :x_axis_left, :string

      # X-axis label for the right side
      attribute :x_axis_right, :string

      # Y-axis label for the bottom
      attribute :y_axis_bottom, :string

      # Y-axis label for the top
      attribute :y_axis_top, :string

      # Label for quadrant 1 (top-right)
      attribute :quadrant_1_label, :string

      # Label for quadrant 2 (top-left)
      attribute :quadrant_2_label, :string

      # Label for quadrant 3 (bottom-left)
      attribute :quadrant_3_label, :string

      # Label for quadrant 4 (bottom-right)
      attribute :quadrant_4_label, :string

      # Collection of data points in the chart
      attribute :points, QuadrantPoint, collection: true, default: -> { [] }

      # Returns the diagram type identifier.
      #
      # @return [Symbol] :quadrant
      def diagram_type
        :quadrant
      end

      # Validates the quadrant chart structure.
      #
      # A quadrant chart is valid if:
      # - All points (if any) are valid
      #
      # Note: Axis labels are optional for minimal diagrams
      #
      # @return [Boolean] true if chart is valid
      def valid?
        return false unless points.all?(&:valid?)

        true
      end

      # Get points grouped by quadrant.
      #
      # @return [Hash<Integer, Array<QuadrantPoint>>] points by quadrant
      def points_by_quadrant
        points.group_by(&:quadrant)
      end
    end
  end
end