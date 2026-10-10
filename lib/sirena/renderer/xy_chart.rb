# frozen_string_literal: true

require_relative "base"
require_relative "../layout/xy_chart"
require_relative "../svg/document"
require_relative "../svg/circle"
require_relative "../svg/line"
require_relative "../svg/rect"
require_relative "../svg/polyline"
require_relative "../svg/text"

module Sirena
  module Renderer
    # Emits SVG from final, typed XY-chart geometry.
    class XyChart < Base
      DEFAULT_COLORS = %w[
        #2563eb #7c3aed #db2777 #ea580c #ca8a04
        #16a34a #0891b2 #4f46e5 #c026d3 #dc2626
      ].freeze

      # @param scene [Layout::XyChart::Scene] final canvas geometry
      # @return [Svg::Document] rendered SVG document
      def render(scene)
        svg = create_document(scene)
        svg << label(scene.title) if scene.title
        render_chart(scene, svg)
        svg
      end

      def render_chart(scene, svg)
        render_lines(scene.lines, svg)
        scene.series.each { |series| render_series(series, svg) }
        render_labels(scene.labels, svg)
        scene.legends.each { |legend| render_legend(legend, svg) }
      end

      def render_lines(lines, svg)
        lines.each { |geometry| svg << line(geometry) }
      end

      def render_labels(labels, svg)
        labels.each { |geometry| svg << label(geometry) }
      end

      protected

      def line(geometry)
        Svg::Line.new.tap do |item|
          assign_line_geometry(item, geometry)
          apply_line_style(item, geometry.kind)
        end
      end

      def assign_line_geometry(item, geometry)
        item.x1 = geometry.x1
        item.y1 = geometry.y1
        item.x2 = geometry.x2
        item.y2 = geometry.y2
      end

      def apply_line_style(item, kind)
        return apply_grid_line_style(item) if kind == "grid"

        item.stroke = theme_color(:axis_line) || "#000000"
        item.stroke_width = "2"
      end

      def apply_grid_line_style(item)
        item.stroke = theme_color(:grid_line) || "#e5e7eb"
        item.stroke_width = "1"
        item.stroke_dasharray = "3,3"
      end

      def label(geometry)
        Svg::Text.new.tap do |text|
          assign_label_geometry(text, geometry)
          apply_label_style(text, geometry)
        end
      end

      def assign_label_geometry(text, geometry)
        text.x = geometry.x
        text.y = geometry.y
        text.text_anchor = geometry.text_anchor
        text.transform = geometry.transform
        text.content = geometry.text
      end

      def apply_label_style(text, geometry)
        text.fill = theme_color(:label_text) || "#000000"
        text.font_size = geometry.font_size.to_s
        text.font_family = theme_typography(:font_family) || "Arial, sans-serif"
        text.font_weight = geometry.font_weight
      end

      def render_series(series, svg)
        colour = dataset_colour(series.colour_index)
        if series.chart_type == :bar
          render_bars(series.bars, colour, svg)
        elsif !series.points.empty?
          render_line_series(series, colour, svg)
        end
      end

      def render_bars(bars, colour, svg)
        bars.each { |bar| svg << bar_element(bar, colour) }
      end

      def render_line_series(series, colour, svg)
        svg << polyline(series, colour)
        series.points.each { |point| svg << point_element(point, colour) }
      end

      def polyline(series, colour)
        Svg::Polyline.new.tap do |item|
          item.points = series.polyline
          item.fill = "none"
          item.stroke = colour
          item.stroke_width = "2"
        end
      end

      def point_element(point, colour)
        Svg::Circle.new.tap do |circle|
          circle.cx = point.x
          circle.cy = point.y
          circle.r = point.radius
          circle.fill = colour
          circle.stroke = theme_color(:background) || "#ffffff"
          circle.stroke_width = "2"
        end
      end

      def bar_element(bar, colour)
        Svg::Rect.new.tap do |rect|
          assign_bar_geometry(rect, bar)
          apply_bar_style(rect, colour)
        end
      end

      def assign_bar_geometry(rect, bar)
        rect.x = bar.x
        rect.y = bar.y
        rect.width = bar.width
        rect.height = bar.height
      end

      def apply_bar_style(rect, colour)
        rect.fill = colour
        rect.fill_opacity = "0.8"
        rect.stroke = colour
        rect.stroke_width = "1"
      end

      def render_legend(legend, svg)
        colour = dataset_colour(legend.colour_index)
        svg << legend_rectangle(legend, colour)
        svg << label(legend.label)
      end

      def legend_rectangle(legend, colour)
        Svg::Rect.new.tap do |rect|
          rect.x = legend.x
          rect.y = legend.y
          rect.width = legend.width
          rect.height = legend.height
          rect.fill = colour
          rect.stroke = "none"
        end
      end

      def dataset_colour(index)
        DEFAULT_COLORS.fetch(index % DEFAULT_COLORS.length)
      end
    end
  end
end
