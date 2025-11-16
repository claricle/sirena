# frozen_string_literal: true

require_relative 'base'
require_relative '../diagram/quadrant'

module Sirena
  module Transform
    # Quadrant chart transformer for converting quadrant models to
    # renderable structure.
    #
    # Like pie charts, quadrant charts have a fixed layout structure
    # (2x2 grid). This transformer validates the diagram and prepares
    # the data with computed SVG coordinates for rendering.
    #
    # @example Transform a quadrant chart
    #   transform = QuadrantTransform.new
    #   data = transform.to_graph(quadrant_diagram)
    class QuadrantTransform < Base
      # Default dimensions for quadrant chart
      DEFAULT_WIDTH = 800
      DEFAULT_HEIGHT = 600
      DEFAULT_MARGIN = 80

      # Converts a quadrant diagram to a renderable data structure.
      #
      # @param diagram [Diagram::QuadrantChart] the quadrant diagram
      # @return [Hash] data structure for rendering with SVG coordinates
      # @raise [TransformError] if diagram is invalid
      def to_graph(diagram)
        raise TransformError, 'Invalid diagram' unless diagram.valid?

        # Calculate dimensions
        width = DEFAULT_WIDTH
        height = DEFAULT_HEIGHT
        margin = DEFAULT_MARGIN

        # Chart area (excluding margins)
        chart_width = width - (margin * 2)
        chart_height = height - (margin * 2)

        {
          id: diagram.id || 'quadrant',
          title: diagram.title,
          dimensions: {
            width: width,
            height: height,
            margin: margin,
            chart_width: chart_width,
            chart_height: chart_height,
            chart_x: margin,
            chart_y: margin
          },
          axes: {
            x_left: diagram.x_axis_left || '',
            x_right: diagram.x_axis_right || '',
            y_bottom: diagram.y_axis_bottom || '',
            y_top: diagram.y_axis_top || ''
          },
          quadrants: {
            q1: {
              label: diagram.quadrant_1_label,
              number: 1,
              bounds: calculate_quadrant_bounds(1, margin, chart_width,
                                                chart_height)
            },
            q2: {
              label: diagram.quadrant_2_label,
              number: 2,
              bounds: calculate_quadrant_bounds(2, margin, chart_width,
                                                chart_height)
            },
            q3: {
              label: diagram.quadrant_3_label,
              number: 3,
              bounds: calculate_quadrant_bounds(3, margin, chart_width,
                                                chart_height)
            },
            q4: {
              label: diagram.quadrant_4_label,
              number: 4,
              bounds: calculate_quadrant_bounds(4, margin, chart_width,
                                                chart_height)
            }
          },
          points: transform_points(diagram, margin, chart_width, chart_height)
        }
      end

      private

      # Calculate bounds for a specific quadrant.
      #
      # @param quadrant [Integer] quadrant number (1-4)
      # @param margin [Float] chart margin
      # @param chart_width [Float] width of chart area
      # @param chart_height [Float] height of chart area
      # @return [Hash] bounds with x, y, width, height
      def calculate_quadrant_bounds(quadrant, margin, chart_width,
                                     chart_height)
        half_width = chart_width / 2.0
        half_height = chart_height / 2.0

        case quadrant
        when 1 # Top-right
          {
            x: margin + half_width,
            y: margin,
            width: half_width,
            height: half_height
          }
        when 2 # Top-left
          {
            x: margin,
            y: margin,
            width: half_width,
            height: half_height
          }
        when 3 # Bottom-left
          {
            x: margin,
            y: margin + half_height,
            width: half_width,
            height: half_height
          }
        when 4 # Bottom-right
          {
            x: margin + half_width,
            y: margin + half_height,
            width: half_width,
            height: half_height
          }
        end
      end

      # Transform points with calculated SVG coordinates.
      #
      # @param diagram [Diagram::QuadrantChart] the diagram
      # @param margin [Float] chart margin
      # @param chart_width [Float] width of chart area
      # @param chart_height [Float] height of chart area
      # @return [Array<Hash>] points with SVG coordinates
      def transform_points(diagram, margin, chart_width, chart_height)
        diagram.points.map.with_index do |point, index|
          # Convert normalized coordinates (0-1) to SVG coordinates
          # Note: Y-axis is inverted in SVG (0 at top)
          svg_x = margin + (point.x * chart_width)
          svg_y = margin + ((1.0 - point.y) * chart_height)

          {
            id: "point_#{index}",
            label: point.label,
            x: point.x,
            y: point.y,
            svg_x: svg_x,
            svg_y: svg_y,
            quadrant: point.quadrant,
            radius: point.radius || 6,
            color: point.color,
            stroke_color: point.stroke_color,
            stroke_width: point.stroke_width || 2,
            index: index
          }
        end
      end
    end
  end
end