# frozen_string_literal: true

require_relative "base"
require_relative "../notation/mermaid/ir_adapters/xychart"

module Sirena
  module Layout
    # Transforms an XyChart diagram into a positioned layout structure.
    #
    # The layout algorithm handles:
    # - Chart area calculation and margins
    # - Axis positioning and scaling
    # - Data point coordinate mapping
    # - Grid line calculations
    #
    # @example Transform an XY chart
    #   transform = Layout::XyChart.new
    #   layout = transform.to_graph(diagram)
    class XyChart < Base
      # Default chart dimensions
      DEFAULT_WIDTH = 800
      DEFAULT_HEIGHT = 500

      # Margins around the chart
      MARGIN_TOP = 80
      MARGIN_RIGHT = 60
      MARGIN_BOTTOM = 80
      MARGIN_LEFT = 100

      GRID_LINES = 5
      BAR_WIDTH_RATIO = 0.6

      class Line < Lutaml::Model::Serializable
        attribute :x1, :float
        attribute :y1, :float
        attribute :x2, :float
        attribute :y2, :float
        attribute :kind, :string
      end

      class Label < Lutaml::Model::Serializable
        attribute :text, :string
        attribute :x, :float
        attribute :y, :float
        attribute :text_anchor, :string
        attribute :font_size, :float
        attribute :font_weight, :string
        attribute :transform, :string
      end

      class Point < Lutaml::Model::Serializable
        attribute :x, :float
        attribute :y, :float
        attribute :radius, :float
      end

      class Bar < Lutaml::Model::Serializable
        attribute :x, :float
        attribute :y, :float
        attribute :width, :float
        attribute :height, :float
      end

      class Series < Lutaml::Model::Serializable
        attribute :id, :string
        attribute :label, :string
        attribute :chart_type, :symbol
        attribute :color, :string
        attribute :colour_index, :integer
        attribute :polyline, :string
        attribute :points, Point, collection: true, default: -> { [] }
        attribute :bars, Bar, collection: true, default: -> { [] }
      end

      class Legend < Lutaml::Model::Serializable
        attribute :x, :float
        attribute :y, :float
        attribute :width, :float
        attribute :height, :float
        attribute :colour_index, :integer
        attribute :label, Label
      end

      class Scene < Layout::Scene
        attribute :view_box, :string
        attribute :title, Label
        attribute :lines, Line, collection: true, default: -> { [] }
        attribute :labels, Label, collection: true, default: -> { [] }
        attribute :series, Series, collection: true, default: -> { [] }
        attribute :legends, Legend, collection: true, default: -> { [] }
      end

      # Transforms the diagram into a layout structure.
      #
      # @param diagram [Diagram::XyChart] the XY chart diagram
      # @return [Hash] layout data with axes, datasets, and dimensions
      def build_graph(diagram)
        data = ir_document(diagram)
        # Calculate plot area
        plot_width = DEFAULT_WIDTH - MARGIN_LEFT - MARGIN_RIGHT
        plot_height = DEFAULT_HEIGHT - MARGIN_TOP - MARGIN_BOTTOM

        # Position axes
        x_axis_layout = position_x_axis(
          axis_data(data, "horizontal_axis"), plot_width
        )
        y_axis_layout = position_y_axis(
          axis_data(data, "vertical_axis"), plot_height
        )

        # Position datasets
        datasets_layout = position_datasets(
          datasets(data),
          x_axis_layout,
          y_axis_layout,
          plot_width,
          plot_height,
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
          title: data.label,
        }
      end

      private

      def scene(diagram)
        graph = build_graph(diagram)
        Scene.new(
          width: graph[:width], height: graph[:height],
          view_box: "0 0 #{graph[:width]} #{graph[:height]}",
          title: title_label(graph),
          lines: grid_lines(graph) + axis_lines(graph),
          labels: axis_labels(graph),
          series: typed_series(graph),
          legends: legends(graph)
        )
      end

      def title_label(graph)
        return unless graph[:title]

        Label.new(text: graph[:title], x: graph[:width] / 2, y: 30,
                  text_anchor: "middle", font_size: large_font_size,
                  font_weight: "bold")
      end

      def grid_lines(graph)
        horizontal_grid_lines(graph) + vertical_grid_lines(graph)
      end

      def horizontal_grid_lines(graph)
        Array.new(GRID_LINES) do |index|
          y = graph[:plot_y] + (index * graph[:plot_height] / GRID_LINES)
          Line.new(
            x1: graph[:plot_x], y1: y,
            x2: graph[:plot_x] + graph[:plot_width], y2: y, kind: "grid"
          )
        end
      end

      def vertical_grid_lines(graph)
        return [] unless graph.dig(:x_axis, :type) == :categorical

        (graph.dig(:x_axis, :positions) || []).map do |position|
          x = graph[:plot_x] + position[:position]
          Line.new(
            x1: x, y1: graph[:plot_y], x2: x,
            y2: graph[:plot_y] + graph[:plot_height], kind: "grid"
          )
        end
      end

      def axis_lines(graph)
        [horizontal_axis_line(graph), vertical_axis_line(graph)]
      end

      def horizontal_axis_line(graph)
        x_coordinate = graph[:plot_x]
        y_coordinate = graph[:plot_y] + graph[:plot_height]
        Line.new(
          x1: x_coordinate, y1: y_coordinate,
          x2: x_coordinate + graph[:plot_width], y2: y_coordinate, kind: "axis"
        )
      end

      def vertical_axis_line(graph)
        x_coordinate = graph[:plot_x]
        y_coordinate = graph[:plot_y]
        Line.new(
          x1: x_coordinate, y1: y_coordinate, x2: x_coordinate,
          y2: y_coordinate + graph[:plot_height], kind: "axis"
        )
      end

      def axis_labels(graph)
        x_axis_labels(graph) + y_axis_labels(graph)
      end

      def x_axis_labels(graph)
        axis = graph[:x_axis]
        [x_axis_title(graph, axis), *x_tick_labels(graph, axis)].compact
      end

      def x_axis_title(graph, axis)
        return unless axis[:label]

        Label.new(
          text: axis[:label], x: graph[:plot_x] + (graph[:plot_width] / 2),
          y: graph[:plot_y] + graph[:plot_height] + 60,
          text_anchor: "middle", font_size: normal_font_size,
          font_weight: "bold"
        )
      end

      def x_tick_labels(graph, axis)
        return [] unless axis[:type] == :categorical

        (axis[:positions] || []).map do |position|
          Label.new(text: position[:label],
                    x: graph[:plot_x] + position[:position],
                    y: graph[:plot_y] + graph[:plot_height] + 20,
                    text_anchor: "middle", font_size: small_font_size)
        end
      end

      def y_axis_labels(graph)
        axis = graph[:y_axis]
        [y_axis_title(graph, axis), *y_tick_labels(graph, axis)].compact
      end

      def y_axis_title(graph, axis)
        return unless axis[:label]

        centre_y = graph[:plot_y] + (graph[:plot_height] / 2)
        Label.new(
          text: axis[:label], x: 20, y: centre_y,
          text_anchor: "middle", font_size: normal_font_size,
          font_weight: "bold", transform: "rotate(-90, 20, #{centre_y})"
        )
      end

      def y_tick_labels(graph, axis)
        Array.new(GRID_LINES) do |index|
          y_tick_label(graph, axis, index)
        end
      end

      def y_tick_label(graph, axis, index)
        Label.new(text: y_tick_value(axis, index), x: graph[:plot_x] - 10,
                  y: y_tick_position(graph, index) + 4,
                  text_anchor: "end", font_size: small_font_size)
      end

      def y_tick_position(graph, index)
        graph[:plot_y] + (index * graph[:plot_height] / GRID_LINES)
      end

      def y_tick_value(axis, index)
        range = axis[:max] - axis[:min]
        (axis[:max] - (index * range / GRID_LINES)).round(1).to_s
      end

      def typed_series(graph)
        graph[:datasets].map.with_index do |dataset, index|
          typed_dataset(graph, dataset, index)
        end
      end

      def typed_dataset(graph, dataset, index)
        points = dataset_points(graph, dataset)
        Series.new(
          id: dataset[:id], label: dataset[:label],
          chart_type: dataset[:chart_type], color: dataset[:color],
          colour_index: index,
          polyline: points.map { |point| "#{point.x},#{point.y}" }.join(" "),
          points: dataset[:chart_type] == :bar ? [] : points,
          bars: dataset[:chart_type] == :bar ? bars(graph, dataset) : []
        )
      end

      def dataset_points(graph, dataset)
        dataset[:points].map do |point|
          Point.new(
            x: graph[:plot_x] + point[:x],
            y: graph[:plot_y] + point[:y], radius: 4
          )
        end
      end

      def bars(graph, dataset)
        width = bar_width(graph)
        dataset[:points].map do |point|
          bar(graph, point, width)
        end
      end

      def bar(graph, point, width)
        Bar.new(x: graph[:plot_x] + point[:x] - (width / 2),
                y: graph[:plot_y] + point[:y], width: width,
                height: graph[:plot_height] - point[:y])
      end

      def bar_width(graph)
        axis = graph[:x_axis]
        return 20 unless axis[:type] == :categorical && axis[:positions]

        (graph[:plot_width] / axis[:positions].length) * BAR_WIDTH_RATIO
      end

      def legends(graph)
        graph[:datasets].map.with_index do |dataset, index|
          legend(graph, dataset, index)
        end
      end

      def legend(graph, dataset, index)
        y = 60 + (index * 25)
        Legend.new(
          x: graph[:width] - 150, y: y - 8, width: 15, height: 15,
          colour_index: index,
          label: Label.new(
            text: dataset[:label], x: graph[:width] - 130,
            y: y + 4, text_anchor: "start", font_size: small_font_size
          )
        )
      end

      def large_font_size
        theme.typography&.font_size_large ||
          Theme::Registry.get(:default).typography.font_size_large
      end

      def normal_font_size
        theme.typography&.font_size_normal ||
          Theme::Registry.get(:default).typography.font_size_normal
      end

      def small_font_size
        theme.typography&.font_size_small ||
          Theme::Registry.get(:default).typography.font_size_small
      end

      def ir_document(diagram)
        return diagram if diagram.is_a?(IR::Prepositioned)

        Notation::Mermaid::IRAdapters::XyChart.call(diagram)
      end

      def axis_data(data, role)
        axis = data.items.find { |item| item.role == role }
        return unless axis

        {
          label: axis.label,
          type: placement_value(axis, "axis_kind").to_sym,
          min: placement_value(axis, "minimum"),
          max: placement_value(axis, "maximum"),
          values: child_values(data, axis.id, "category"),
        }
      end

      def datasets(data)
        data.items.select { |item| item.role == "data_series" }
          .sort_by { |item| placement_value(item, "series_order") }
          .map { |item| dataset(data, item) }
      end

      def dataset(data, item)
        {
          id: item.id, label: item.label,
          chart_type: placement_value(item, "chart_kind").to_sym,
          color: placement_value(item, "series_color"),
          values: child_values(data, item.id, "value")
        }
      end

      def child_values(data, parent_id, dimension)
        data.items.select { |item| item.parent_id == parent_id }
          .filter_map { |item| placement(item, dimension) }
          .sort_by(&:ordinal).map { |value| value.value.value }
      end

      def placement_value(item, dimension)
        placement(item, dimension)&.value&.value
      end

      def placement(item, dimension)
        item.placements.find { |candidate| candidate.dimension == dimension }
      end

      # Positions the X-axis.
      #
      # @param axis [Diagram::XYAxis] X-axis
      # @param width [Numeric] plot width
      # @return [Hash] X-axis layout
      def position_x_axis(axis, width)
        return default_x_axis(width) unless axis

        if axis[:type] == :categorical
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
        num_categories = axis[:values].length
        return default_x_axis(width) if num_categories.zero?

        # Calculate spacing between categories
        spacing = width / [num_categories, 1].max

        # Position each category
        positions = axis[:values].map.with_index do |label, idx|
          {
            label: label,
            position: idx * spacing + spacing / 2,
            index: idx,
          }
        end

        {
          label: axis[:label],
          type: :categorical,
          positions: positions,
          min: 0,
          max: num_categories - 1,
          width: width,
        }
      end

      # Positions a numeric X-axis.
      #
      # @param axis [Diagram::XYAxis] axis
      # @param width [Numeric] plot width
      # @return [Hash] axis layout
      def position_numeric_axis(axis, width)
        min = axis[:min]
        max = axis[:max]

        {
          label: axis[:label],
          type: :numeric,
          min: min,
          max: max,
          width: width,
          scale: width / (max - min).to_f,
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
          scale: width / 10.0,
        }
      end

      # Positions the Y-axis.
      #
      # @param axis [Diagram::XYAxis] Y-axis
      # @param height [Numeric] plot height
      # @return [Hash] Y-axis layout
      def position_y_axis(axis, height)
        return default_y_axis(height) unless axis

        min = axis[:min] || 0
        max = axis[:max] || 100

        {
          label: axis[:label],
          min: min,
          max: max,
          height: height,
          scale: height / (max - min).to_f,
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
          scale: height / 100.0,
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
            height,
          )

          {
            id: dataset[:id],
            label: dataset[:label],
            chart_type: dataset[:chart_type],
            color: dataset[:color],
            points: points,
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
        dataset[:values].map.with_index do |y_value, idx|
          x = calculate_x_position(idx, x_axis, width)
          y = calculate_y_position(y_value, y_axis, height)

          {
            x: x,
            y: y,
            value: y_value,
            index: idx,
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
