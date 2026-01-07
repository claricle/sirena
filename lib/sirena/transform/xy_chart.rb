# frozen_string_literal: true

module Sirena
  module Transform
    # Transforms an XYChart diagram into a positioned layout structure.
    #
    # The layout algorithm handles:
    # - Chart area calculation and margins
    # - Axis positioning and scaling
    # - Data point coordinate mapping
    # - Grid line calculations
    #
    # @example Transform an XY chart
    #   transform = Transform::XYChart.new
    #   layout = transform.to_graph(diagram)
    class XYChart
      # Default chart dimensions
      DEFAULT_WIDTH = 800
      DEFAULT_HEIGHT = 500

      # Margins around the chart
      MARGIN_TOP = 80
      MARGIN_RIGHT = 60
      MARGIN_BOTTOM = 80
      MARGIN_LEFT = 100

      # Transforms the diagram into a layout structure.
      #
      # @param diagram [Diagram::XYChart] the XY chart diagram
      # @return [Hash] layout data with axes, datasets, and dimensions
      def to_graph(diagram)
        # Calculate plot area
        plot_width = DEFAULT_WIDTH - MARGIN_LEFT - MARGIN_RIGHT
        plot_height = DEFAULT_HEIGHT - MARGIN_TOP - MARGIN_BOTTOM

        # Position axes
        x_axis_layout = position_x_axis(diagram.x_axis, plot_width)
        y_axis_layout = position_y_axis(diagram.y_axis, plot_height)

        # Position datasets
        datasets_layout = position_datasets(
          diagram.datasets,
          x_axis_layout,
          y_axis_layout,
          plot_width,
          plot_height
        )

        {
          width: DEFAULT_WIDTH,
          height: DEFAULT_HEIGHT,
          plot_x: MARGIN_LEFT,
          plot_y: MARGIN_TOP,
          plot_width: plot_width,
          plot_height: plot_height,
          x_axis: x_axis_layout,
          y_axis: y_axis_layout,
          datasets: datasets_layout,
          title: diagram.title
        }
      end

      private

      # Positions the X-axis.
      #
      # @param axis [Diagram::XYAxis] X-axis
      # @param width [Numeric] plot width
      # @return [Hash] X-axis layout
      def position_x_axis(axis, width)
        return default_x_axis(width) unless axis

        if axis.categorical?
          position_categorical_axis(axis, width)
        else
          position_numeric_axis(axis, width)
        end
      end

      # Positions a categorical X-axis.
      #
      # @param axis [Diagram::XYAxis] axis
      # @param width [Numeric] plot width
      # @return [Hash] axis layout
      def position_categorical_axis(axis, width)
        num_categories = axis.values.length
        return default_x_axis(width) if num_categories == 0

        # Calculate spacing between categories
        spacing = width / [num_categories, 1].max

        # Position each category
        positions = axis.values.map.with_index do |label, idx|
          {
            label: label,
            position: idx * spacing + spacing / 2,
            index: idx
          }
        end

        {
          label: axis.label,
          type: :categorical,
          positions: positions,
          min: 0,
          max: num_categories - 1,
          width: width
        }
      end

      # Positions a numeric X-axis.
      #
      # @param axis [Diagram::XYAxis] axis
      # @param width [Numeric] plot width
      # @return [Hash] axis layout
      def position_numeric_axis(axis, width)
        min, max = axis.range

        {
          label: axis.label,
          type: :numeric,
          min: min,
          max: max,
          width: width,
          scale: width / (max - min).to_f
        }
      end

      # Returns a default X-axis layout.
      #
      # @param width [Numeric] plot width
      # @return [Hash] default axis layout
      def default_x_axis(width)
        {
          label: nil,
          type: :numeric,
          min: 0,
          max: 10,
          width: width,
          scale: width / 10.0
        }
      end

      # Positions the Y-axis.
      #
      # @param axis [Diagram::XYAxis] Y-axis
      # @param height [Numeric] plot height
      # @return [Hash] Y-axis layout
      def position_y_axis(axis, height)
        return default_y_axis(height) unless axis

        min = axis.min || 0
        max = axis.max || 100

        {
          label: axis.label,
          min: min,
          max: max,
          height: height,
          scale: height / (max - min).to_f
        }
      end

      # Returns a default Y-axis layout.
      #
      # @param height [Numeric] plot height
      # @return [Hash] default axis layout
      def default_y_axis(height)
        {
          label: nil,
          min: 0,
          max: 100,
          height: height,
          scale: height / 100.0
        }
      end

      # Positions all datasets.
      #
      # @param datasets [Array<Diagram::XYDataset>] datasets
      # @param x_axis [Hash] X-axis layout
      # @param y_axis [Hash] Y-axis layout
      # @param width [Numeric] plot width
      # @param height [Numeric] plot height
      # @return [Array<Hash>] positioned datasets
      def position_datasets(datasets, x_axis, y_axis, width, height)
        datasets.map do |dataset|
          points = position_dataset_points(
            dataset,
            x_axis,
            y_axis,
            width,
            height
          )

          {
            id: dataset.id,
            label: dataset.label,
            chart_type: dataset.chart_type,
            points: points
          }
        end
      end

      # Positions points for a single dataset.
      #
      # @param dataset [Diagram::XYDataset] dataset
      # @param x_axis [Hash] X-axis layout
      # @param y_axis [Hash] Y-axis layout
      # @param width [Numeric] plot width
      # @param height [Numeric] plot height
      # @return [Array<Hash>] positioned points
      def position_dataset_points(dataset, x_axis, y_axis, width, height)
        dataset.values.map.with_index do |y_value, idx|
          x = calculate_x_position(idx, x_axis, width)
          y = calculate_y_position(y_value, y_axis, height)

          {
            x: x,
            y: y,
            value: y_value,
            index: idx
          }
        end
      end

      # Calculates X position for a data point.
      #
      # @param index [Integer] data point index
      # @param x_axis [Hash] X-axis layout
      # @param width [Numeric] plot width
      # @return [Numeric] X coordinate
      def calculate_x_position(index, x_axis, width)
        if x_axis[:type] == :categorical && x_axis[:positions]
          # Use pre-calculated positions for categories
          position = x_axis[:positions][index]
          position ? position[:position] : 0
        else
          # Distribute points evenly across width
          num_points = 1 # Will be overridden by caller if needed
          spacing = width / [index + 1, 1].max
          index * spacing
        end
      end

      # Calculates Y position for a data point.
      #
      # @param value [Numeric] Y value
      # @param y_axis [Hash] Y-axis layout
      # @param height [Numeric] plot height
      # @return [Numeric] Y coordinate (inverted, 0 is top)
      def calculate_y_position(value, y_axis, height)
        # Normalize value to 0-1 range
        normalized = normalize_value(value, y_axis[:min], y_axis[:max])

        # Convert to pixel position (inverted, 0 is top)
        height - (normalized * height)
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
    end
  end
end