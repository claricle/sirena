# frozen_string_literal: true

require_relative "base"
require_relative "../notation/mermaid/ir_adapters/quadrant"

module Sirena
  module Layout
    # Builds final quadrant-chart geometry.
    class Quadrant < Base
      # mmdc's quadrantChart defaults (mermaid quadrantBuilder.ts).
      CHART_SIZE = 500
      PADDING = 5
      AXIS_LABEL_PADDING = 5
      AXIS_FONT_SIZE = 16
      QUADRANT_FONT_SIZE = 16
      QUADRANT_TEXT_TOP_PADDING = 5
      TITLE_PADDING = 10
      TITLE_FONT_SIZE = 20
      POINT_FONT_SIZE = 12
      POINT_TEXT_PADDING = 5
      EXTERNAL_BORDER = 2
      INTERNAL_BORDER = 1

      # The plotted area inside the chart's padding, axes and title.
      Space = Data.define(:left, :top, :width, :height, :title, :x_axis,
                          :x_axis_below) do
        def half_width = width / 2.0
        def half_height = height / 2.0
      end

      class Rect < Lutaml::Model::Serializable
        attribute :number, :integer
        attribute :x, :float
        attribute :y, :float
        attribute :width, :float
        attribute :height, :float
      end

      class Line < Lutaml::Model::Serializable
        attribute :x1, :float
        attribute :y1, :float
        attribute :x2, :float
        attribute :y2, :float
        attribute :stroke_width, :float
      end

      class Label < Lutaml::Model::Serializable
        attribute :text, :string
        attribute :x, :float
        attribute :y, :float
        attribute :font_size, :float
        attribute :text_anchor, :string
        attribute :font_weight, :string
        attribute :style, :string
        attribute :rotation, :float
        attribute :baseline, :string
      end

      class Point < Lutaml::Model::Serializable
        attribute :id, :string
        attribute :x, :float
        attribute :y, :float
        attribute :radius, :float
        attribute :quadrant, :integer
        attribute :color, :string
        attribute :stroke_color, :string
        attribute :stroke_width, :float
        attribute :label, Label
      end

      class Scene < Layout::Scene
        attribute :id, :string
        attribute :view_box, :string
        attribute :title, Label
        attribute :quadrants, Rect, collection: true, default: -> { [] }
        attribute :axes, Line, collection: true, default: -> { [] }
        attribute :axis_labels, Label, collection: true, default: -> { [] }
        attribute :quadrant_labels, Label, collection: true, default: -> { [] }
        attribute :points, Point, collection: true, default: -> { [] }
      end

      # Retains the pre-Scene structure for direct callers during conversion.
      def build_graph(diagram)
        data = ir_document(diagram)
        space = chart_space(data)
        {
          id: data.id, title: data.label, space: space,
          axes: axes(data),
          quadrants: quadrants(data, space),
          points: transform_points(data, space)
        }
      end

      private

      def scene(diagram)
        graph = build_graph(diagram)
        Scene.new(
          id: graph[:id], width: CHART_SIZE, height: CHART_SIZE,
          view_box: "0 0 #{CHART_SIZE} #{CHART_SIZE}",
          **scene_data(graph)
        )
      end

      def scene_data(graph)
        space = graph[:space]
        {
          title: title_label(graph[:title]),
          quadrants: typed_quadrants(graph[:quadrants]),
          axes: border_lines(space),
          axis_labels: axis_labels(graph[:axes], space),
          quadrant_labels: quadrant_labels(graph[:quadrants], graph[:points]),
          points: typed_points(graph[:points])
        }
      end

      def chart_space(data)
        axes = axes(data)
        title = title_space(data)
        x_axis = axes.values_at(:x_left, :x_right).any? { |t| !t.empty? }
        y_axis = axes.values_at(:y_bottom, :y_top).any? { |t| !t.empty? }
        x_space = x_axis ? (2 * AXIS_LABEL_PADDING) + AXIS_FONT_SIZE : 0
        y_space = y_axis ? (2 * AXIS_LABEL_PADDING) + AXIS_FONT_SIZE : 0
        x_top = points?(data) ? 0 : x_space
        x_bottom = points?(data) ? x_space : 0
        Space.new(
          left: PADDING + y_space, top: PADDING + x_top + title,
          width: CHART_SIZE - (2 * PADDING) - y_space,
          height: CHART_SIZE - (2 * PADDING) - x_top - x_bottom - title,
          title: title, x_axis: x_axis, x_axis_below: points?(data)
        )
      end

      def title_space(data)
        return 0 if data.label.to_s.empty?

        TITLE_FONT_SIZE + (2 * TITLE_PADDING)
      end

      def points?(data)
        data.items.any? { |item| item.role == "point" }
      end

      def ir_document(diagram)
        return diagram if diagram.is_a?(IR::Prepositioned)

        Notation::Mermaid::IRAdapters::Quadrant.call(diagram)
      end

      def axes(data)
        labels = axis_labels_for(data)
        { x_left: labels["x_min"] || "", x_right: labels["x_max"] || "",
          y_bottom: labels["y_min"] || "", y_top: labels["y_max"] || "" }
      end

      def axis_labels_for(data)
        data.items.select { |item| item.role == "axis_label" }
          .to_h { |item| [placement_value(item, "axis_position"), item.label] }
      end

      def quadrants(data, space)
        labels = data.items.select { |item| item.role == "region_label" }
          .to_h { |item| [placement_value(item, "region").to_i, item.label] }
        (1..4).to_h do |number|
          [:"q#{number}", {
            label: labels[number], number: number,
            bounds: quadrant_bounds(number, space)
          }]
        end
      end

      def quadrant_bounds(number, space)
        x = [1, 4].include?(number) ? space.left + space.half_width : space.left
        y = [3, 4].include?(number) ? space.top + space.half_height : space.top
        { x: x, y: y, width: space.half_width, height: space.half_height }
      end

      def title_label(title)
        return if title.to_s.empty?

        label(title, [CHART_SIZE / 2.0, TITLE_PADDING], TITLE_FONT_SIZE,
              "title", anchor: "middle", baseline: "hanging")
      end

      def typed_quadrants(quadrants)
        quadrants.values.map do |quadrant|
          Rect.new(number: quadrant[:number], **quadrant[:bounds])
        end
      end

      # The six border lines mmdc draws: four outer edges, then the two dividers.
      def border_lines(space)
        half = EXTERNAL_BORDER / 2.0
        left = space.left
        top = space.top
        right = left + space.width
        bottom = top + space.height
        mid_x = left + space.half_width
        mid_y = top + space.half_height
        [
          line(left - half, top, right + half, top, EXTERNAL_BORDER),
          line(right, top + half, right, bottom - half, EXTERNAL_BORDER),
          line(left - half, bottom, right + half, bottom, EXTERNAL_BORDER),
          line(left, top + half, left, bottom - half, EXTERNAL_BORDER),
          line(mid_x, top + half, mid_x, bottom - half, INTERNAL_BORDER),
          line(left + half, mid_y, right - half, mid_y, INTERNAL_BORDER),
        ]
      end

      def line(x1, y1, x2, y2, width)
        Line.new(x1: x1, y1: y1, x2: x2, y2: y2, stroke_width: width)
      end

      # Only axis labels that were written are drawn, as in mmdc.
      def axis_labels(axes, space)
        x_labels(axes, space) + y_labels(axes, space)
      end

      def x_labels(axes, space)
        middle = !axes[:x_right].empty?
        y = x_label_y(space)
        centre = space.left + (middle ? space.half_width / 2 : 0)
        [[axes[:x_left], centre],
         [axes[:x_right], centre + space.half_width]].filter_map do |text, x|
          next if text.empty?

          axis_label(text, [x, y], middle, 0)
        end
      end

      # The x axis sits below the plot when there are points, above otherwise.
      def x_label_y(space)
        return AXIS_LABEL_PADDING + space.title unless space.x_axis_below

        AXIS_LABEL_PADDING + space.top + space.height + PADDING
      end

      def y_labels(axes, space)
        middle = !axes[:y_top].empty?
        lift = middle ? space.half_height / 2 : 0
        [[axes[:y_bottom], space.top + space.height - lift],
         [axes[:y_top], space.top + space.half_height - lift]]
          .filter_map do |text, y|
            next if text.empty?

            axis_label(text, [AXIS_LABEL_PADDING, y], middle, -90)
          end
      end

      def axis_label(text, position, middle, rotation)
        label(text, position, AXIS_FONT_SIZE, "axis",
              anchor: middle ? "middle" : "start", baseline: "hanging",
              rotation: rotation)
      end

      def quadrant_labels(quadrants, points)
        quadrants.values.filter_map do |quadrant|
          next unless quadrant[:label]

          bounds = quadrant[:bounds]
          x = bounds[:x] + (bounds[:width] / 2.0)
          next top_label(quadrant[:label], x, bounds) unless points.empty?

          label(quadrant[:label], [x, bounds[:y] + (bounds[:height] / 2.0)],
                QUADRANT_FONT_SIZE, "quadrant", anchor: "middle",
                baseline: "middle")
        end
      end

      def top_label(text, x, bounds)
        label(text, [x, bounds[:y] + QUADRANT_TEXT_TOP_PADDING],
              QUADRANT_FONT_SIZE, "quadrant", anchor: "middle",
              baseline: "hanging")
      end

      def typed_points(points)
        points.map { |point| typed_point(point) }
      end

      def typed_point(point)
        Point.new(
          id: point[:id], x: point[:svg_x], y: point[:svg_y],
          radius: point[:radius], quadrant: point[:quadrant],
          color: point[:color], stroke_color: point[:stroke_color],
          stroke_width: point[:stroke_width], label: point_label(point)
        )
      end

      def point_label(point)
        label(
          point[:label], [point[:svg_x], point[:svg_y] + POINT_TEXT_PADDING],
          POINT_FONT_SIZE, "point", anchor: "middle", baseline: "hanging"
        )
      end

      def label(text, position, size, style, **options)
        Label.new(
          text: text, x: position[0], y: position[1],
          font_size: size, style: style,
          text_anchor: options[:anchor], font_weight: options[:weight],
          rotation: options.fetch(:rotation, 0), baseline: options[:baseline]
        )
      end

      def transform_points(data, space)
        point_items(data).map { |point| transform_point(point, space) }
      end

      def transform_point(point, space)
        values = point_values(point)
        { id: point.id, label: point.label, quadrant: point_quadrant(point) }
          .merge(point_coordinates(values, space))
          .merge(point_style(values))
      end

      def point_values(point)
        %w[x_value y_value marker_size fill_color stroke_color stroke_width]
          .to_h { |dimension| [dimension, placement_value(point, dimension)] }
      end

      def point_coordinates(values, space)
        {
          svg_x: space.left + (values["x_value"] * space.width),
          svg_y: space.top + ((1.0 - values["y_value"]) * space.height),
        }
      end

      def point_style(values)
        {
          radius: values["marker_size"].to_f, color: values["fill_color"],
          stroke_color: values["stroke_color"],
          stroke_width: values["stroke_width"].to_f
        }
      end

      def point_quadrant(point)
        quadrant_number(placement_value(point, "x_value"),
                        placement_value(point, "y_value"))
      end

      def point_items(data)
        data.items.select { |item| item.role == "point" }
          .sort_by { |item| placement(item, "x_value").ordinal }
      end

      def placement_value(item, dimension)
        placement(item, dimension)&.value&.value
      end

      def placement(item, dimension)
        item.placements.find { |candidate| candidate.dimension == dimension }
      end

      def quadrant_number(x_value, y_value)
        return x_value >= 0.5 ? 1 : 2 if y_value >= 0.5

        x_value < 0.5 ? 3 : 4
      end
    end
  end
end
