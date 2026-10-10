# frozen_string_literal: true

require_relative "base"
require_relative "../notation/mermaid/ir_adapters/radar"

module Sirena
  module Layout
    # Builds final-canvas radar-chart geometry.
    class Radar < Base
      DEFAULT_RADIUS = 200
      PADDING = 80
      LABEL_OFFSET = 30
      GRID_CIRCLES = 5

      class Circle < Lutaml::Model::Serializable
        attribute :x, :float
        attribute :y, :float
        attribute :radius, :float
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
        attribute :dominant_baseline, :string
        attribute :font_weight, :string
      end

      class Axis < Lutaml::Model::Serializable
        attribute :id, :string
        attribute :angle, :float
        attribute :line, Line
        attribute :label, Label
      end

      class Point < Lutaml::Model::Serializable
        attribute :axis_id, :string
        attribute :value, :float
        attribute :normalized, :float
        attribute :x, :float
        attribute :y, :float
      end

      class Curve < Lutaml::Model::Serializable
        attribute :id, :string
        attribute :label, :string
        attribute :polygon_points, :string
        attribute :points, Point, collection: true, default: -> { [] }
        attribute :color_index, :integer
      end

      class Legend < Lutaml::Model::Serializable
        attribute :marker, Circle
        attribute :label, Label
        attribute :color_index, :integer
      end

      class Scene < Layout::Scene
        attribute :view_box, :string
        attribute :center_x, :float
        attribute :center_y, :float
        attribute :radius, :float
        attribute :min_value, :float
        attribute :max_value, :float
        attribute :grid_circles, Circle, collection: true, default: -> { [] }
        attribute :axes, Axis, collection: true, default: -> { [] }
        attribute :curves, Curve, collection: true, default: -> { [] }
        attribute :legend, Legend, collection: true, default: -> { [] }
      end

      # Converts the released positioned-Hash surface to a typed Scene.
      def self.from_graph(graph, theme: nil)
        layout = new
        layout.theme = theme if theme
        layout.send(:scene_from_graph, graph)
      end

      # Retains the pre-Scene structure for direct callers during conversion.
      def build_graph(diagram)
        data = ir_data(diagram)
        return empty_layout if data.dimensions.empty?

        min_value, max_value = calculate_value_range(data)
        axes = position_axes(data)
        radar_dimensions(min_value, max_value).merge(
          radar_data(data, axes, min_value, max_value),
        )
      end

      private

      def ir_data(diagram)
        return diagram if diagram.is_a?(IR::Data)

        Notation::Mermaid::IRAdapters::Radar.call(diagram)
      end

      def scene(diagram)
        scene_from_graph(build_graph(diagram))
      end

      def scene_from_graph(graph)
        curves = typed_curves(
          graph.fetch(:curves), graph.fetch(:center_x), graph.fetch(:center_y)
        )
        Scene.new(**scene_dimensions(graph), **scene_data(graph, curves))
      end

      def scene_dimensions(graph)
        width = graph.fetch(:width)
        height = graph.fetch(:height)
        {
          width: width, height: height, view_box: "0 0 #{width} #{height}",
          center_x: graph.fetch(:center_x), center_y: graph.fetch(:center_y),
          radius: graph.fetch(:radius), min_value: graph.fetch(:min_value),
          max_value: graph.fetch(:max_value)
        }
      end

      def scene_data(graph, curves)
        center_x = graph.fetch(:center_x)
        center_y = graph.fetch(:center_y)
        {
          grid_circles: typed_grid(
            graph.fetch(:grid_circles), center_x, center_y
          ),
          axes: typed_axes(graph.fetch(:axes), center_x, center_y),
          curves: curves, legend: legend(graph, curves)
        }
      end

      def typed_grid(circles, center_x, center_y)
        circles.map do |circle|
          Circle.new(x: center_x, y: center_y, radius: circle[:radius])
        end
      end

      def typed_axes(axes, center_x, center_y)
        axes.map { |axis| typed_axis(axis, center_x, center_y) }
      end

      def typed_axis(axis, center_x, center_y)
        angle = axis[:angle_degrees]
        Axis.new(
          id: axis[:id], angle: angle,
          line: axis_line(axis, center_x, center_y),
          label: axis_label(axis, angle, center_x, center_y)
        )
      end

      def axis_line(axis, center_x, center_y)
        Line.new(
          x1: center_x, y1: center_y,
          x2: center_x + axis[:end_x], y2: center_y + axis[:end_y]
        )
      end

      def axis_label(axis, angle, center_x, center_y)
        Label.new(
          text: axis[:label], x: center_x + axis[:label_x],
          y: center_y + axis[:label_y],
          font_size: font_size(:font_size_normal, 12),
          text_anchor: text_anchor(angle),
          dominant_baseline: dominant_baseline(angle), font_weight: "bold"
        )
      end

      def typed_curves(curves, center_x, center_y)
        curves.map.with_index do |curve, index|
          typed_curve(curve, index, center_x, center_y)
        end
      end

      def typed_curve(curve, index, center_x, center_y)
        points = curve[:points].map do |point|
          typed_point(point, center_x, center_y)
        end
        Curve.new(
          id: curve[:id], label: curve[:label], points: points,
          polygon_points: polygon_points(points), color_index: index
        )
      end

      def typed_point(point, center_x, center_y)
        Point.new(
          axis_id: point[:axis_id], value: point[:value],
          normalized: point[:normalized], x: center_x + point[:x],
          y: center_y + point[:y]
        )
      end

      def polygon_points(points)
        points.map { |point| "#{point.x},#{point.y}" }.join(" ")
      end

      def legend(graph, curves)
        return [] if graph.dig(:options, :show_legend) == false

        curves.map.with_index do |curve, index|
          legend_entry(curve, index, graph.fetch(:height))
        end
      end

      def legend_entry(curve, index, height)
        y_position = height - 40 + (index * 20)
        Legend.new(
          marker: Circle.new(x: 20, y: y_position, radius: 5),
          label: Label.new(
            text: curve.label, x: 35, y: y_position + 4,
            font_size: font_size(:font_size_small, 10), text_anchor: "start"
          ),
          color_index: index,
        )
      end

      def text_anchor(angle)
        normalized = angle % 360
        return "start" if normalized > 45 && normalized < 135
        return "end" if normalized > 225 && normalized < 315

        "middle"
      end

      def dominant_baseline(angle)
        normalized = angle % 360
        return "hanging" if normalized > 135 && normalized < 225
        return "auto" if normalized < 45 || normalized > 315

        "middle"
      end

      def font_size(name, fallback)
        value = theme.typography&.public_send(name)
        value&.positive? ? value : fallback
      end

      def empty_layout
        {
          axes: [], curves: [], grid_circles: [], center_x: PADDING,
          center_y: PADDING, radius: DEFAULT_RADIUS, width: PADDING * 2,
          height: PADDING * 2, min_value: 0, max_value: 0, options: {}
        }
      end

      def radar_dimensions(min_value, max_value)
        center = DEFAULT_RADIUS + PADDING
        {
          center_x: center, center_y: center, radius: DEFAULT_RADIUS,
          width: center * 2, height: center * 2,
          min_value: min_value, max_value: max_value
        }
      end

      def radar_data(data, axes, min_value, max_value)
        {
          axes: axes,
          curves: position_curves(data, axes, min_value, max_value),
          grid_circles: calculate_grid_circles(min_value, max_value),
          options: radar_options(data),
        }
      end

      def calculate_value_range(data)
        measurements = data.values
        values = measurements.filter_map do |value|
          value.value.value if value.role == "measurement"
        end
        lower_bound = option_value(data, "lower_bound")
        upper_bound = option_value(data, "upper_bound")
        min_value = lower_bound || values.min || 0
        max_value = upper_bound || inferred_max(values)
        max_value = min_value + 1 if max_value <= min_value
        [min_value, max_value]
      end

      def inferred_max(values)
        values.max || 100
      end

      def position_axes(data)
        step = 360.0 / data.dimensions.length
        data.dimensions.map.with_index do |axis, index|
          positioned_axis(data, axis, index, step)
        end
      end

      def positioned_axis(data, axis, index, step)
        angle = (index * step) - 90
        radians = angle * Math::PI / 180.0
        axis_coordinates(radians).merge(
          id: source_id(data, axis), ir_id: axis.id, label: axis.label,
          angle_degrees: angle, angle_radians: radians, index: index
        )
      end

      def axis_coordinates(radians)
        {
          end_x: Math.cos(radians) * DEFAULT_RADIUS,
          end_y: Math.sin(radians) * DEFAULT_RADIUS,
          label_x: Math.cos(radians) * (DEFAULT_RADIUS + LABEL_OFFSET),
          label_y: Math.sin(radians) * (DEFAULT_RADIUS + LABEL_OFFSET),
        }
      end

      def position_curves(data, axes, min_value, max_value)
        data.series.map do |series|
          positioned_curve(data, series, axes, min_value, max_value)
        end
      end

      def positioned_curve(data, series, axes, min_value, max_value)
        points = axes.map do |axis|
          positioned_point(data, series, axis, min_value, max_value)
        end
        { id: source_id(data, series), label: series.label, points: points }
      end

      def positioned_point(data, series, axis, min_value, max_value)
        value = measurement(data, series.id, axis[:ir_id])
        normalized = normalize_value(value, min_value, max_value)
        radius = normalized * DEFAULT_RADIUS
        {
          axis_id: axis[:id], value: value, normalized: normalized,
          x: Math.cos(axis[:angle_radians]) * radius,
          y: Math.sin(axis[:angle_radians]) * radius,
          angle: axis[:angle_radians]
        }
      end

      def measurement(data, series_id, dimension_id)
        value = data.values.find do |entry|
          entry.role == "measurement" && entry.series_id == series_id &&
            entry.dimension_id == dimension_id
        end
        value ? value.value.value : 0.0
      end

      def radar_options(data)
        visibility = data.values.find do |value|
          value.role == "legend_visibility"
        end
        visibility ? { show_legend: visibility.value.value } : {}
      end

      def option_value(data, role)
        value = data.values.find { |entry| entry.role == role }
        value&.value&.value
      end

      def source_id(data, item)
        identifier = data.values.find do |value|
          value.role == "identifier" && value.parent_id == item.id
        end
        identifier ? identifier.value.value : item.id
      end

      def normalize_value(value, min_value, max_value)
        return 0 if max_value == min_value

        ((value - min_value).to_f / (max_value - min_value)).clamp(0, 1)
      end

      def calculate_grid_circles(min_value, max_value)
        Array.new(GRID_CIRCLES) do |index|
          fraction = (index + 1).to_f / GRID_CIRCLES
          {
            radius: DEFAULT_RADIUS * fraction,
            value: min_value + ((max_value - min_value) * fraction),
            fraction: fraction,
          }
        end
      end
    end
  end
end
