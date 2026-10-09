# frozen_string_literal: true

require_relative "base"

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
        return empty_layout if diagram.axes.empty?

        min_value, max_value = calculate_value_range(diagram)
        axes = position_axes(diagram.axes)
        {
          axes: axes,
          curves: position_curves(diagram.curves, axes, min_value, max_value),
          grid_circles: calculate_grid_circles(min_value, max_value),
          center_x: DEFAULT_RADIUS + PADDING, center_y: DEFAULT_RADIUS + PADDING,
          radius: DEFAULT_RADIUS, width: (DEFAULT_RADIUS + PADDING) * 2,
          height: (DEFAULT_RADIUS + PADDING) * 2,
          min_value: min_value, max_value: max_value, options: diagram.options
        }
      end

      private

      def scene(diagram)
        scene_from_graph(build_graph(diagram))
      end

      def scene_from_graph(graph)
        center_x = graph.fetch(:center_x)
        center_y = graph.fetch(:center_y)
        width = graph.fetch(:width)
        height = graph.fetch(:height)
        curves = typed_curves(graph.fetch(:curves), center_x, center_y)
        Scene.new(
          width: width, height: height, view_box: "0 0 #{width} #{height}",
          center_x: center_x, center_y: center_y, radius: graph.fetch(:radius),
          min_value: graph.fetch(:min_value), max_value: graph.fetch(:max_value),
          grid_circles: typed_grid(graph.fetch(:grid_circles), center_x, center_y),
          axes: typed_axes(graph.fetch(:axes), center_x, center_y), curves: curves,
          legend: legend(graph, curves)
        )
      end

      def typed_grid(circles, center_x, center_y)
        circles.map do |circle|
          Circle.new(x: center_x, y: center_y, radius: circle[:radius])
        end
      end

      def typed_axes(axes, center_x, center_y)
        axes.map do |axis|
          angle = axis[:angle_degrees]
          Axis.new(
            id: axis[:id], angle: angle,
            line: Line.new(
              x1: center_x, y1: center_y,
              x2: center_x + axis[:end_x], y2: center_y + axis[:end_y]
            ),
            label: Label.new(
              text: axis[:label], x: center_x + axis[:label_x],
              y: center_y + axis[:label_y],
              font_size: font_size(:font_size_normal, 12),
              text_anchor: text_anchor(angle),
              dominant_baseline: dominant_baseline(angle), font_weight: "bold"
            )
          )
        end
      end

      def typed_curves(curves, center_x, center_y)
        curves.map.with_index do |curve, index|
          points = curve[:points].map do |point|
            Point.new(
              axis_id: point[:axis_id], value: point[:value],
              normalized: point[:normalized], x: center_x + point[:x],
              y: center_y + point[:y]
            )
          end
          Curve.new(
            id: curve[:id], label: curve[:label], points: points,
            polygon_points: points.map { |point| "#{point.x},#{point.y}" }.join(" "),
            color_index: index
          )
        end
      end

      def legend(graph, curves)
        return [] if graph.dig(:options, :show_legend) == false

        curves.map.with_index do |curve, index|
          y = graph.fetch(:height) - 40 + (index * 20)
          Legend.new(
            marker: Circle.new(x: 20, y: y, radius: 5),
            label: Label.new(
              text: curve.label, x: 35, y: y + 4,
              font_size: font_size(:font_size_small, 10), text_anchor: "start"
            ),
            color_index: index,
          )
        end
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

      def calculate_value_range(diagram)
        values = diagram.curves.flat_map { |curve| curve.values.values }
        min_value = diagram.options[:min] || values.min || 0
        max_value = diagram.options[:max] || values.max || 100
        max_value = min_value + 1 if max_value <= min_value
        [min_value, max_value]
      end

      def position_axes(axes)
        step = 360.0 / axes.length
        axes.map.with_index do |axis, index|
          angle = (index * step) - 90
          radians = angle * Math::PI / 180.0
          {
            id: axis.id, label: axis.label, angle_degrees: angle,
            angle_radians: radians, end_x: Math.cos(radians) * DEFAULT_RADIUS,
            end_y: Math.sin(radians) * DEFAULT_RADIUS,
            label_x: Math.cos(radians) * (DEFAULT_RADIUS + LABEL_OFFSET),
            label_y: Math.sin(radians) * (DEFAULT_RADIUS + LABEL_OFFSET),
            index: index
          }
        end
      end

      def position_curves(curves, axes, min_value, max_value)
        curves.map do |curve|
          points = axes.map do |axis|
            value = curve.value_for(axis[:id])
            normalized = normalize_value(value, min_value, max_value)
            radius = normalized * DEFAULT_RADIUS
            {
              axis_id: axis[:id], value: value, normalized: normalized,
              x: Math.cos(axis[:angle_radians]) * radius,
              y: Math.sin(axis[:angle_radians]) * radius,
              angle: axis[:angle_radians]
            }
          end
          { id: curve.id, label: curve.label, points: points }
        end
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
