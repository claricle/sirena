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
      # Error box dimensions
      BOX_WIDTH = 400
      BOX_HEIGHT = 120
      BOX_X = 50
      BOX_Y = 50
      ICON_CENTER_X = 100
      ICON_CENTER_Y = 110
      ICON_RADIUS = 20
      TEXT_X = 140
      TEXT_Y = 105

      # Renders an error diagram to SVG.
      #
      # @param graph [Hash] the error diagram graph structure from transform
      # @return [Svg::Document] the rendered SVG document
      def render(graph)
        scene = typed_scene(graph)
        svg = create_document(scene)

        # Render error box
        render_error_box(scene, svg)

        # Render error icon
        render_typed_error_icon(svg, scene)

        # Render error text
        render_error_text(scene, svg)

        svg
      end

      protected

      def render_error_box(graph, svg)
        geometry = typed_scene(graph).box
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

      def render_error_icon(svg)
        render_typed_error_icon(svg, Layout::Error.from_graph({}))
      end

      def render_typed_error_icon(svg, scene)
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

      def render_error_text(graph, svg)
        scene = typed_scene(graph)
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

      def typed_scene(graph)
        return graph if graph.is_a?(Layout::Error::Scene)

        Layout::Error.from_graph(graph, theme: theme)
      end

      def number_string(value)
        value.to_i == value ? value.to_i.to_s : value.to_s
      end
    end
  end
end
