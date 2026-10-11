# frozen_string_literal: true

require_relative "base"
require_relative "../layout/error"
require_relative "../svg/document"
require_relative "../svg/rect"
require_relative "../svg/text"
require_relative "../svg/circle"
require_relative "../svg/path"

module Sirena
  module Renderer
    # Error diagram renderer for converting error diagrams to SVG.
    #
    # Renders an error message box with a warning icon and error text.
    #
    # @example Render an error diagram
    #   renderer = Error.new
    #   svg = renderer.render(error_diagram)
    class Error < Base
      # Renders an error diagram to SVG.
      #
      # @param scene [Layout::Error::Scene] the final error scene
      # @return [Svg::Document] the rendered SVG document
      def render(scene)
        svg = create_document(scene)

        # Render error box
        render_error_box(scene, svg)

        # Render error icon
        render_error_icon(scene, svg)

        # Render error text
        render_error_text(scene, svg)

        svg
      end

      protected

      def render_error_box(scene, svg)
        geometry = scene.box
        box = Svg::Rect.new.tap do |r|
          r.x = geometry.x
          r.y = geometry.y
          r.width = geometry.width
          r.height = geometry.height
          r.fill = theme_color(:surface)
          r.stroke = theme_color(:error)
          r.stroke_width = "2"
          r.rx = geometry.corner_radius
          r.ry = geometry.corner_radius
        end

        svg << box
      end

      def render_error_icon(scene, svg)
        # Error icon circle
        circle = Svg::Circle.new.tap do |c|
          c.cx = scene.icon.x
          c.cy = scene.icon.y
          c.r = scene.icon.radius
          c.fill = theme_color(:error)
          c.stroke = theme_color(:edge_stroke)
          c.stroke_width = "2"
        end
        svg << circle

        # Exclamation mark - vertical line
        line = Svg::Rect.new.tap do |r|
          r.x = scene.mark.x
          r.y = scene.mark.y
          r.width = scene.mark.width
          r.height = scene.mark.height
          r.fill = theme_color(:background)
          r.rx = scene.mark.corner_radius
        end
        svg << line

        # Exclamation mark - dot
        dot = Svg::Circle.new.tap do |c|
          c.cx = scene.dot.x
          c.cy = scene.dot.y
          c.r = scene.dot.radius
          c.fill = theme_color(:background)
        end
        svg << dot
      end

      def render_error_text(scene, svg)
        [scene.label, scene.version_label].each do |label|
          svg << text_element(label)
        end
      end

      def text_element(label)
        Svg::Text.new.tap do |t|
          t.x = label.x
          t.y = label.y
          t.content = label.text
          t.fill = theme_color(:error)
          t.font_family = theme_typography(:font_family) ||
            "Arial, sans-serif"
          t.font_size = number_string(label.font_size)
          t.text_anchor = label.text_anchor
          t.font_weight = label.font_weight
        end
      end

      def number_string(value)
        value.to_i == value ? value.to_i.to_s : value.to_s
      end
    end
  end
end
