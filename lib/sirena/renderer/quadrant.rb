# frozen_string_literal: true

require_relative "base"
require_relative "../layout/quadrant"
require_relative "../svg/document"
require_relative "../svg/rect"
require_relative "../svg/line"
require_relative "../svg/circle"
require_relative "../svg/text"

module Sirena
  module Renderer
    # Emits SVG from final, typed quadrant-chart geometry.
    class Quadrant < Base
      QUADRANT_COLORS = {
        1 => "#e3f2fd", 2 => "#fff3e0", 3 => "#f3e5f5", 4 => "#e8f5e9"
      }.freeze

      # @param scene [Layout::Quadrant::Scene] final chart geometry
      # @return [Svg::Document] rendered SVG document
      def render(scene)
        svg = document(scene)
        svg << text_element(scene.title) if scene.title
        scene.quadrants.each { |quadrant| svg << quadrant_element(quadrant) }
        scene.axes.each { |axis| svg << axis_element(axis) }
        scene.axis_labels.each { |label| svg << text_element(label) }
        scene.quadrant_labels.each { |label| svg << text_element(label) }
        scene.points.each { |point| render_point(point, svg) }
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

      def quadrant_element(quadrant)
        Svg::Rect.new.tap do |rect|
          rect.x = quadrant.x
          rect.y = quadrant.y
          rect.width = quadrant.width
          rect.height = quadrant.height
          rect.fill = quadrant_color(quadrant.number)
          rect.stroke = theme_color(:grid_line) || "#cccccc"
          rect.stroke_width = "1"
          rect.opacity = "0.3"
        end
      end

      def axis_element(axis)
        Svg::Line.new.tap do |line|
          line.x1 = axis.x1
          line.y1 = axis.y1
          line.x2 = axis.x2
          line.y2 = axis.y2
          line.stroke = theme_color(:grid_line) || "#666666"
          line.stroke_width = "2"
        end
      end

      def render_point(point, svg)
        svg << Svg::Circle.new.tap do |circle|
          circle.cx = point.x
          circle.cy = point.y
          circle.r = point.radius
          circle.fill = point.color || point_color(point.quadrant)
          circle.stroke =
            point.stroke_color || theme_color(:node_stroke) || "#ffffff"
          circle.stroke_width = number_string(point.stroke_width)
          circle.id = point.id
        end
        svg << text_element(point.label)
      end

      def text_element(label)
        Svg::Text.new.tap do |text|
          text.x = label.x
          text.y = label.y
          text.content = label.text
          text.fill = label_color(label.style)
          text.font_family =
            theme_typography(:font_family) || "Arial, sans-serif"
          text.font_size = number_string(label.font_size)
          text.text_anchor = label.text_anchor if label.text_anchor
          text.font_weight = label.font_weight if label.font_weight
          text.opacity = "0.7" if label.style == "quadrant"
        end
      end

      def label_color(style)
        return theme_color(:label_text) || "#666666" if style == "axis"
        return theme_color(:label_text) || "#333333" if style == "quadrant"

        theme_color(:label_text) || "#000000"
      end

      def quadrant_color(number)
        theme_color(:"quadrant_#{number}") || QUADRANT_COLORS[number]
      end

      def point_color(number)
        {
          1 => theme_color(:primary) || "#2196f3",
          2 => theme_color(:secondary) || "#ff9800",
          3 => theme_color(:accent) || "#9c27b0",
          4 => theme_color(:success) || "#4caf50",
        }.fetch(number, theme_color(:primary) || "#2196f3")
      end

      def number_string(value)
        value.to_i == value ? value.to_i.to_s : value.to_s
      end
    end
  end
end
