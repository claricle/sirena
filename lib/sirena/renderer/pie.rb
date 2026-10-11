# frozen_string_literal: true

require_relative "base"
require_relative "../layout/pie"
require_relative "../svg/document"
require_relative "../svg/circle"
require_relative "../svg/path"
require_relative "../svg/rect"
require_relative "../svg/text"
require_relative "../svg/group"

module Sirena
  module Renderer
    # Pie chart renderer for converting pie diagrams to SVG.
    #
    # Converts a Pie diagram model into SVG with calculated slice angles,
    # colors from theme, labels, and optional data values.
    #
    # @example Render a pie chart
    #   renderer = Pie.new
    #   svg = renderer.render(pie_diagram)
    class Pie < Base
      # Renders a pie chart diagram to SVG.
      #
      # @param scene [Layout::Pie::Scene] final pie geometry
      # @return [Svg::Document] the rendered SVG document
      def render(scene)
        svg = create_document(scene)
        svg << outer_circle(scene.ring)
        svg << typed_label(scene.title) if scene.title
        scene.slices.each { |slice| add_slice(svg, slice) }
        scene.legend.each { |entry| add_legend_entry(svg, entry) }
        svg
      end

      protected

      def outer_circle(ring)
        Svg::Circle.new(
          cx: ring.cx, cy: ring.cy, r: ring.radius,
          fill: "none", stroke_width: "2",
          stroke: theme_color(:label_text)
        )
      end

      def add_slice(svg, slice)
        svg << typed_slice(slice)
        svg << typed_label(slice.label)
      end

      def typed_slice(slice)
        Svg::Path.new.tap do |path|
          path.d = slice.path
          path.fill = get_slice_color(slice.color_index)
          path.stroke = theme_color(:node_stroke)
          path.stroke_width = "2"
          path.id = slice.id.sub("_", "-")
        end
      end

      def add_legend_entry(svg, entry)
        color = get_slice_color(entry.color_index)
        svg << Svg::Rect.new(x: entry.x, y: entry.y,
                             width: entry.width, height: entry.height,
                             fill: color, stroke: color)
        svg << legend_text(entry)
      end

      def legend_text(entry)
        Svg::Text.new.tap do |text|
          text.x = entry.text_x
          text.y = entry.text_y
          text.content = entry.text
          apply_text_theme(text, entry.font_size)
        end
      end

      def apply_text_theme(text, font_size)
        text.fill = theme_color(:label_text)
        text.font_family = theme_typography(:font_family) || "Arial, sans-serif"
        text.font_size = number_string(font_size)
      end

      def typed_label(label)
        Svg::Text.new.tap do |text|
          set_label_geometry(text, label)
          set_label_style(text, label)
        end
      end

      def set_label_geometry(text, label)
        text.x = label.x
        text.y = label.y
        text.text_anchor = label.text_anchor
        text.dominant_baseline = label.dominant_baseline
      end

      def set_label_style(text, label)
        text.content = label.text
        apply_text_theme(text, label.font_size)
        text.font_weight = label.font_weight if label.font_weight
      end

      def number_string(value)
        value.to_i == value ? value.to_i.to_s : value.to_s
      end

      def get_slice_color(index)
        theme.colors.palette(:pie, index)
      end
    end
  end
end
