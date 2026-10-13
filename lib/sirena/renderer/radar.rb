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
      # @param scene [Layout::Radar::Scene, Hash] final geometry or released
      #   positioned-Hash input
      # @return [Svg::Document] rendered SVG document
      def render(scene)
        scene = typed_scene(scene)
        svg = create_document(scene)
        render_grid(scene, svg)
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

        grid_polygon(ring)
      end

      def grid_polygon(ring)
        Svg::Polygon.new.tap do |element|
          element.points = ring.polygon_points
          style_ring(element)
        end
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
        element.stroke = theme_color(:radar_grid_line)
        element.stroke_width = "1"
        element.class_name = "radarGraticule"
      end

      def render_axis(axis, svg)
        svg << axis_line(axis.line)
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
          circle.r = point.radius
          circle.fill = color
          circle.stroke = theme_color(:background)
          circle.stroke_width = "1"
        end
      end

      def render_legend(entry, svg)
        svg << legend_marker(entry.marker, curve_color(entry.color_index))
        svg << label_element(entry.label)
      end

      def label_element(label)
        Svg::Text.new.tap do |text|
          text.x = label.x
          text.y = label.y
          style_label(text, label)
          text.content = label.text
        end
      end

      def curve_color(index)
        theme.colors.palette(:radar, index)
      end

      def number_string(value)
        value.to_i == value ? value.to_i.to_s : value.to_s
      end

      private

      def render_grid(scene, svg)
        scene.grid_circles.each { |ring| svg << grid_ring(ring, scene) }
        scene.axes.each { |axis| render_axis(axis, svg) }
      end

      def axis_line(geometry)
        Svg::Line.new.tap do |line|
          line.x1 = geometry.x1
          line.y1 = geometry.y1
          line.x2 = geometry.x2
          line.y2 = geometry.y2
          style_axis_line(line)
        end
      end

      def style_axis_line(line)
        line.stroke = theme_color(:radar_axis_line)
        line.stroke_width = "1"
        line.class_name = "radarAxisLine"
      end

      def legend_marker(marker, color)
        Svg::Circle.new.tap do |circle|
          circle.cx = marker.x
          circle.cy = marker.y
          circle.r = marker.radius
          circle.fill = color
          circle.stroke = "none"
        end
      end

      def style_label(text, label)
        text.text_anchor = label.text_anchor
        text.fill = theme_color(:label_text)
        apply_label_typography(text, label)
        text.class_name = label.class_name
      end

      def apply_label_typography(text, label)
        text.font_size = number_string(label.font_size)
        text.font_family = label_font_family
        text.font_weight = label.font_weight if label.font_weight
      end

      def label_font_family
        theme_typography(:font_family) || "Arial, sans-serif"
      end
    end
  end
end
