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
        box = rectangle_geometry(geometry)
        box.fill = theme_color(:surface)
        box.stroke = theme_color(:error)
        box.stroke_width = "2"
        box.rx = geometry.corner_radius
        box.ry = geometry.corner_radius
        svg << box
      end

      def render_error_icon(scene, svg)
        svg << error_icon_circle(scene.icon)
        svg << error_icon_mark(scene.mark)
        svg << error_icon_dot(scene.dot)
      end

      def render_error_text(scene, svg)
        [scene.label, scene.version_label].each do |label|
          svg << text_element(label)
        end
      end

      def text_element(label)
        Svg::Text.new.tap do |text|
          position_error_text(text, label)
          text.content = label.text
          style_error_text(text, label)
        end
      end

      def number_string(value)
        value.to_i == value ? value.to_i.to_s : value.to_s
      end

      private

      def rectangle_geometry(geometry)
        Svg::Rect.new.tap do |rect|
          rect.x = geometry.x
          rect.y = geometry.y
          rect.width = geometry.width
          rect.height = geometry.height
        end
      end

      def circle_geometry(geometry)
        Svg::Circle.new.tap do |circle|
          circle.cx = geometry.x
          circle.cy = geometry.y
          circle.r = geometry.radius
        end
      end

      def error_icon_circle(geometry)
        circle_geometry(geometry).tap do |circle|
          circle.fill = theme_color(:error)
          circle.stroke = theme_color(:edge_stroke)
          circle.stroke_width = "2"
        end
      end

      def error_icon_mark(geometry)
        rectangle_geometry(geometry).tap do |rect|
          rect.fill = theme_color(:background)
          rect.rx = geometry.corner_radius
        end
      end

      def error_icon_dot(geometry)
        circle_geometry(geometry).tap do |circle|
          circle.fill = theme_color(:background)
        end
      end

      def position_error_text(text, label)
        text.x = label.x
        text.y = label.y
      end

      def style_error_text(text, label)
        text.fill = theme_color(:error)
        text.font_family = theme_typography(:font_family) || "Arial, sans-serif"
        text.font_size = number_string(label.font_size)
        text.text_anchor = label.text_anchor
        text.font_weight = label.font_weight
      end
    end
  end
end
