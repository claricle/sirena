# frozen_string_literal: true

module Sirena
  module Transform
    # Transforms a RadarChart diagram into a positioned layout structure.
    #
    # The layout algorithm handles:
    # - Radial axis positioning (360° / num_axes)
    # - Data point plotting on each axis
    # - Value normalization and scaling
    # - Polar to cartesian coordinate conversion
    # - Polygon formation for each dataset
    #
    # @example Transform a radar chart
    #   transform = Transform::Radar.new
    #   layout = transform.to_graph(diagram)
    class Radar
      # Default radius of the chart
      DEFAULT_RADIUS = 200

      # Padding around the chart
      PADDING = 80

      # Label distance from the chart center
      LABEL_OFFSET = 30

      # Number of grid circles to draw
      GRID_CIRCLES = 5

      # Transforms the diagram into a layout structure.
      #
      # @param diagram [Diagram::RadarChart] the radar chart diagram
      # @return [Hash] layout data with axes, curves, and dimensions
      def to_graph(diagram)
        num_axes = diagram.axes.length
        return empty_layout if num_axes == 0

        # Calculate value range
        min_value, max_value = calculate_value_range(diagram)

        # Position axes radially
        positioned_axes = position_axes(diagram.axes, num_axes)

        # Position data points for each curve
        positioned_curves = position_curves(
          diagram.curves,
          positioned_axes,
          min_value,
          max_value
        )

        # Calculate grid circles for reference
        grid_circles = calculate_grid_circles(min_value, max_value)

        {
          axes: positioned_axes,
          curves: positioned_curves,
          grid_circles: grid_circles,
          center_x: DEFAULT_RADIUS + PADDING,
          center_y: DEFAULT_RADIUS + PADDING,
          radius: DEFAULT_RADIUS,
          width: (DEFAULT_RADIUS + PADDING) * 2,
          height: (DEFAULT_RADIUS + PADDING) * 2,
          min_value: min_value,
          max_value: max_value
        }
      end

      private

      # Returns an empty layout structure.
      #
      # @return [Hash] empty layout
      def empty_layout
        {
          axes: [],
          curves: [],
          grid_circles: [],
          center_x: PADDING,
          center_y: PADDING,
          radius: DEFAULT_RADIUS,
          width: PADDING * 2,
          height: PADDING * 2,
          min_value: 0,
          max_value: 0
        }
      end

      # Calculates the value range from all curves.
      #
      # @param diagram [Diagram::RadarChart] diagram
      # @return [Array<Numeric, Numeric>] min and max values
      def calculate_value_range(diagram)
        all_values = diagram.curves.flat_map { |c| c.values.values }

        # Use configured min/max if available
        min_value = diagram.options[:min] || all_values.min || 0
        max_value = diagram.options[:max] || all_values.max || 100

        # Ensure max > min
        max_value = min_value + 1 if max_value <= min_value

        [min_value, max_value]
      end

      # Positions axes radially around the center.
      #
      # @param axes [Array<Diagram::RadarAxis>] axes
      # @param num_axes [Integer] number of axes
      # @return [Array<Hash>] positioned axes
      def position_axes(axes, num_axes)
        positioned = []
        angle_step = 360.0 / num_axes

        axes.each_with_index do |axis, idx|
          # Calculate angle (start at top, go clockwise)
          angle_degrees = idx * angle_step - 90 # -90 to start at top
          angle_radians = angle_degrees * Math::PI / 180.0

          # Calculate end point of axis line
          end_x = Math.cos(angle_radians) * DEFAULT_RADIUS
          end_y = Math.sin(angle_radians) * DEFAULT_RADIUS

          # Calculate label position (beyond the end point)
          label_radius = DEFAULT_RADIUS + LABEL_OFFSET
          label_x = Math.cos(angle_radians) * label_radius
          label_y = Math.sin(angle_radians) * label_radius

          positioned << {
            id: axis.id,
            label: axis.label,
            angle_degrees: angle_degrees,
            angle_radians: angle_radians,
            end_x: end_x,
            end_y: end_y,
            label_x: label_x,
            label_y: label_y,
            index: idx
          }
        end

        positioned
      end

      # Positions data points for all curves.
      #
      # @param curves [Array<Diagram::RadarCurve>] curves
      # @param positioned_axes [Array<Hash>] positioned axes
      # @param min_value [Numeric] minimum value
      # @param max_value [Numeric] maximum value
      # @return [Array<Hash>] positioned curves with points
      def position_curves(curves, positioned_axes, min_value, max_value)
        positioned = []

        curves.each do |curve|
          points = []

          positioned_axes.each do |axis|
            value = curve.value_for(axis[:id])

            # Normalize value to 0-1 range
            normalized = normalize_value(value, min_value, max_value)

            # Calculate radius for this value
            radius = normalized * DEFAULT_RADIUS

            # Convert to cartesian coordinates
            x = Math.cos(axis[:angle_radians]) * radius
            y = Math.sin(axis[:angle_radians]) * radius

            points << {
              axis_id: axis[:id],
              value: value,
              normalized: normalized,
              x: x,
              y: y,
              angle: axis[:angle_radians]
            }
          end

          positioned << {
            id: curve.id,
            label: curve.label,
            points: points
          }
        end

        positioned
      end

      # Normalizes a value to the 0-1 range.
      #
      # @param value [Numeric] value to normalize
      # @param min_value [Numeric] minimum value
      # @param max_value [Numeric] maximum value
      # @return [Numeric] normalized value
      def normalize_value(value, min_value, max_value)
        return 0 if max_value == min_value

        ((value - min_value).to_f / (max_value - min_value)).clamp(0, 1)
      end

      # Calculates grid circle positions.
      #
      # @param min_value [Numeric] minimum value
      # @param max_value [Numeric] maximum value
      # @return [Array<Hash>] grid circles with radius and label
      def calculate_grid_circles(min_value, max_value)
        circles = []

        GRID_CIRCLES.times do |i|
          fraction = (i + 1).to_f / GRID_CIRCLES
          radius = DEFAULT_RADIUS * fraction
          value = min_value + (max_value - min_value) * fraction

          circles << {
            radius: radius,
            value: value,
            fraction: fraction
          }
        end

        circles
      end
    end
  end
end