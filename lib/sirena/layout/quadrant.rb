# frozen_string_literal: true

require_relative "base"
require_relative "../notation/mermaid/ir_adapters/quadrant"

module Sirena
  module Layout
    # Builds final quadrant-chart geometry.
    class Quadrant < Base
      DEFAULT_WIDTH = 800
      DEFAULT_HEIGHT = 600
      DEFAULT_MARGIN = 80

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
      end

      class Label < Lutaml::Model::Serializable
        attribute :text, :string
        attribute :x, :float
        attribute :y, :float
        attribute :font_size, :float
        attribute :text_anchor, :string
        attribute :font_weight, :string
        attribute :style, :string
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
        margin, chart_width, chart_height = chart_dimensions
        {
          id: data.id, title: data.label,
          dimensions: dimensions(margin, chart_width, chart_height),
          axes: axes(data),
          quadrants: quadrants(data, margin, chart_width, chart_height),
          points: transform_points(data, margin, chart_width, chart_height)
        }
      end

      private

      def scene(diagram)
        graph = build_graph(diagram)
        dims = graph[:dimensions]
        Scene.new(
          **canvas_attributes(graph, dims),
          **scene_data(graph, dims),
        )
      end

      def canvas_attributes(graph, dims)
        {
          id: graph[:id], width: dims[:width], height: dims[:height],
          view_box: "0 0 #{dims[:width]} #{dims[:height]}"
        }
      end

      def scene_data(graph, dims)
        {
          title: title_label(graph[:title], dims),
          quadrants: typed_quadrants(graph[:quadrants]),
          axes: axis_lines(dims), axis_labels: axis_labels(graph[:axes], dims),
          quadrant_labels: quadrant_labels(graph[:quadrants]),
          points: typed_points(graph[:points])
        }
      end

      def dimensions(margin, chart_width, chart_height)
        {
          width: DEFAULT_WIDTH, height: DEFAULT_HEIGHT, margin: margin,
          chart_width: chart_width, chart_height: chart_height,
          chart_x: margin, chart_y: margin
        }
      end

      def chart_dimensions
        [DEFAULT_MARGIN, DEFAULT_WIDTH - (DEFAULT_MARGIN * 2),
         DEFAULT_HEIGHT - (DEFAULT_MARGIN * 2)]
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

      def quadrants(data, margin, width, height)
        labels = data.items.select { |item| item.role == "region_label" }
          .to_h { |item| [placement_value(item, "region").to_i, item.label] }
        (1..4).to_h do |number|
          [:"q#{number}", {
            label: labels[number], number: number,
            bounds: calculate_quadrant_bounds(number, margin, width, height)
          }]
        end
      end

      def title_label(title, dims)
        return unless title

        label(title, [dims[:width] / 2.0, 30],
              font_size(:font_size_large, 18), "title",
              anchor: "middle", weight: "bold")
      end

      def typed_quadrants(quadrants)
        quadrants.values.map do |quadrant|
          bounds = quadrant[:bounds]
          Rect.new(number: quadrant[:number], **bounds)
        end
      end

      def axis_lines(dims)
        center_x = dims[:chart_x] + (dims[:chart_width] / 2.0)
        center_y = dims[:chart_y] + (dims[:chart_height] / 2.0)
        [
          vertical_axis(dims, center_x), horizontal_axis(dims, center_y)
        ]
      end

      def vertical_axis(dims, center_x)
        Line.new(
          x1: center_x, y1: dims[:chart_y], x2: center_x,
          y2: dims[:chart_y] + dims[:chart_height]
        )
      end

      def horizontal_axis(dims, center_y)
        Line.new(
          x1: dims[:chart_x], y1: center_y,
          x2: dims[:chart_x] + dims[:chart_width], y2: center_y
        )
      end

      def axis_labels(axes, dims)
        size = font_size(:font_size_small, 12)
        bottom = dims[:chart_y] + dims[:chart_height]
        right = dims[:chart_x] + dims[:chart_width]
        [
          label(axes[:x_left], [dims[:chart_x] - 10, bottom + 30], size,
                "axis", anchor: "end"),
          label(axes[:x_right], [right + 10, bottom + 30], size,
                "axis", anchor: "start"),
          label(axes[:y_bottom], [dims[:chart_x] - 30, bottom + 10], size,
                "axis", anchor: "middle"),
          label(axes[:y_top], [dims[:chart_x] - 30, dims[:chart_y] - 10], size,
                "axis", anchor: "middle"),
        ]
      end

      def quadrant_labels(quadrants)
        quadrants.values.filter_map do |quadrant|
          next unless quadrant[:label]

          bounds = quadrant[:bounds]
          label(
            quadrant[:label],
            [bounds[:x] + (bounds[:width] / 2.0), bounds[:y] + 20],
            font_size(:font_size_normal, 14), "quadrant",
            anchor: "middle", weight: "bold"
          )
        end
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
        position = [point[:svg_x] + 10, point[:svg_y] - 10]
        label(
          point[:label], position, font_size(:font_size_small, 11),
          "point", anchor: "start"
        )
      end

      def label(text, position, size, style, **options)
        Label.new(
          text: text, x: position[0], y: position[1],
          font_size: size, style: style,
          text_anchor: options[:anchor], font_weight: options[:weight]
        )
      end

      def font_size(name, fallback)
        value = theme.typography&.public_send(name)
        value&.positive? ? value : fallback
      end

      def calculate_quadrant_bounds(number, margin, width, height)
        half_width = width / 2.0
        half_height = height / 2.0
        x = [1, 4].include?(number) ? margin + half_width : margin
        y = [3, 4].include?(number) ? margin + half_height : margin
        { x: x, y: y, width: half_width, height: half_height }
      end

      def transform_points(data, margin, width, height)
        point_items(data).map do |point|
          transform_point(point, margin, width, height)
        end
      end

      def transform_point(point, margin, width, height)
        {
          id: point.id, label: point.label,
          svg_x: margin + (placement_value(point, "x_value") * width),
          svg_y: margin + ((1.0 - placement_value(point, "y_value")) * height),
          quadrant: point_quadrant(point),
          radius: placement_value(point, "marker_size").to_f,
          color: placement_value(point, "fill_color"),
          stroke_color: placement_value(point, "stroke_color"),
          stroke_width: placement_value(point, "stroke_width").to_f
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
