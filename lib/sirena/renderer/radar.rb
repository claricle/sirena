# frozen_string_literal: true

require_relative "base"
require_relative "../layout/radar"
require_relative "../svg/document"
require_relative "../svg/circle"
require_relative "../svg/line"
require_relative "../svg/path"
require_relative "../svg/polygon"
require_relative "../svg/text"

module Sirena
  module Renderer
    # Emits SVG from final, typed radar-chart geometry.
    class Radar < Base
      DEFAULT_COLORS = %w[
        #2563eb #7c3aed #db2777 #ea580c #ca8a04
        #16a34a #0891b2 #4f46e5 #c026d3 #dc2626
      ].freeze

      # @param scene [Layout::Radar::Scene, Hash] final geometry or released
      #   positioned-Hash input
      # @return [Svg::Document] rendered SVG document
      def render(scene)
        scene = typed_scene(scene)
        svg = create_document(scene)
        scene.grid_circles.each { |ring| svg << grid_ring(ring, scene) }
        scene.axes.each { |axis| render_axis(axis, svg) }
        scene.curves.each { |curve| render_curve(curve, svg, scene) }
        scene.legend.each { |entry| render_legend(entry, svg) }
        svg << label_element(scene.title) if scene.title
        svg
      end

      protected

      def typed_scene(scene)
        return scene if scene.is_a?(Layout::Radar::Scene)

        Layout::Radar.from_graph(scene, theme: theme)
      end

      def grid_ring(ring, scene)
        return grid_circle(ring) unless scene.grid_shape == "polygon"

        grid_polygon(ring, scene)
      end

      def grid_polygon(ring, scene)
        Svg::Polygon.new.tap do |element|
          element.points = scene.axes.map { |axis| ring_point(ring, axis) }
            .join(" ")
          style_ring(element)
        end
      end

      def ring_point(ring, axis)
        radians = axis.angle * Math::PI / 180
        x_pos = ring.x + (Math.cos(radians) * ring.radius)
        y_pos = ring.y + (Math.sin(radians) * ring.radius)
        "#{x_pos},#{y_pos}"
      end

      def grid_circle(circle)
        Svg::Circle.new.tap do |element|
          element.cx = circle.x
          element.cy = circle.y
          element.r = circle.radius
          style_ring(element)
        end
      end

      def style_ring(element)
        element.fill = "none"
        element.stroke = theme_color(:grid_line) || "#e5e7eb"
        element.stroke_width = "1"
        element.class_name = "radarGraticule"
      end

      def render_axis(axis, svg)
        svg << Svg::Line.new.tap do |line|
          line.x1 = axis.line.x1
          line.y1 = axis.line.y1
          line.x2 = axis.line.x2
          line.y2 = axis.line.y2
          line.stroke = theme_color(:axis_line) || "#9ca3af"
          line.stroke_width = "1"
          line.class_name = "radarAxisLine"
        end
        svg << label_element(axis.label)
      end

      def render_curve(curve, svg, scene)
        return if curve.points.empty?

        color = curve_color(curve.color_index)
        svg << curve_shape(curve, color, scene)
        curve.points.each { |point| svg << point_element(point, color) }
      end

      def curve_shape(curve, color, scene)
        return curve_path(curve, color) unless scene.grid_shape == "polygon"

        curve_polygon(curve, color)
      end

      def curve_polygon(curve, color)
        Svg::Polygon.new.tap do |polygon|
          polygon.points = curve.polygon_points
          paint_curve(polygon, curve, color)
        end
      end

      def curve_path(curve, color)
        Svg::Path.new.tap do |path|
          path.d = curve.path_data
          paint_curve(path, curve, color)
        end
      end

      def paint_curve(shape, curve, color)
        shape.class_name = "radarCurve-#{curve.color_index}"
        shape.fill = color
        shape.fill_opacity = "0.3"
        shape.stroke = color
        shape.stroke_width = "2"
      end

      def point_element(point, color)
        Svg::Circle.new.tap do |circle|
          circle.cx = point.x
          circle.cy = point.y
          circle.r = 3
          circle.fill = color
          circle.stroke = theme_color(:background) || "#ffffff"
          circle.stroke_width = "1"
        end
      end

      def render_legend(entry, svg)
        color = curve_color(entry.color_index)
        svg << Svg::Circle.new.tap do |circle|
          circle.cx = entry.marker.x
          circle.cy = entry.marker.y
          circle.r = entry.marker.radius
          circle.fill = color
          circle.stroke = "none"
        end
        svg << label_element(entry.label)
      end

      def label_element(label)
        Svg::Text.new.tap do |text|
          text.x = label.x
          text.y = label.y
          text.text_anchor = label.text_anchor
          if label.dominant_baseline
            text.dominant_baseline = label.dominant_baseline
          end
          text.fill = theme_color(:label_text) || "#000000"
          text.font_size = number_string(label.font_size)
          text.font_family =
            theme_typography(:font_family) || "Arial, sans-serif"
          text.font_weight = label.font_weight if label.font_weight
          text.class_name = label.class_name
          text.content = label.text
        end
      end

      def curve_color(index)
        DEFAULT_COLORS[index % DEFAULT_COLORS.length]
      end

      def number_string(value)
        value.to_i == value ? value.to_i.to_s : value.to_s
      end
    end
  end
end
