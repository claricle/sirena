# frozen_string_literal: true

require_relative "base"
require_relative "../layout/radar"
require_relative "../svg/document"
require_relative "../svg/circle"
require_relative "../svg/line"
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
        scene = Layout::Radar.from_graph(scene, theme: theme) unless scene.is_a?(Layout::Radar::Scene)
        svg = document(scene)
        scene.grid_circles.each { |circle| svg << grid_circle(circle) }
        scene.axes.each { |axis| render_axis(axis, svg) }
        scene.curves.each { |curve| render_curve(curve, svg) }
        scene.legend.each { |entry| render_legend(entry, svg) }
        svg
      end

      protected

      def document(scene)
        Svg::Document.new.tap do |svg|
          svg.width = scene.width
          svg.height = scene.height
          svg.view_box = scene.view_box
        end
      end

      def grid_circle(circle)
        Svg::Circle.new.tap do |element|
          element.cx = circle.x
          element.cy = circle.y
          element.r = circle.radius
          element.fill = "none"
          element.stroke = theme_color(:grid_line) || "#e5e7eb"
          element.stroke_width = "1"
        end
      end

      def render_axis(axis, svg)
        svg << Svg::Line.new.tap do |line|
          line.x1 = axis.line.x1
          line.y1 = axis.line.y1
          line.x2 = axis.line.x2
          line.y2 = axis.line.y2
          line.stroke = theme_color(:axis_line) || "#9ca3af"
          line.stroke_width = "1"
        end
        svg << label_element(axis.label)
      end

      def render_curve(curve, svg)
        return if curve.points.empty?

        color = curve_color(curve.color_index)
        svg << Svg::Polygon.new.tap do |polygon|
          polygon.points = curve.polygon_points
          polygon.fill = color
          polygon.fill_opacity = "0.3"
          polygon.stroke = color
          polygon.stroke_width = "2"
        end
        curve.points.each { |point| svg << point_element(point, color) }
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
          text.dominant_baseline = label.dominant_baseline if label.dominant_baseline
          text.fill = theme_color(:label_text) || "#000000"
          text.font_size = number_string(label.font_size)
          text.font_family = theme_typography(:font_family) || "Arial, sans-serif"
          text.font_weight = label.font_weight if label.font_weight
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
