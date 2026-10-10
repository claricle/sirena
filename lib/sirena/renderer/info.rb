# frozen_string_literal: true

require_relative "base"
require_relative "../layout/info"
require_relative "../svg/document"
require_relative "../svg/rect"
require_relative "../svg/text"

module Sirena
  module Renderer
    # Info diagram renderer for converting info diagrams to SVG.
    #
    # Renders a simple informational message box with centered text.
    #
    # @example Render an info diagram
    #   renderer = Info.new
    #   svg = renderer.render(info_diagram)
    class Info < Base
      # Info box dimensions
      BOX_WIDTH = 400
      BOX_HEIGHT = 100
      BOX_X = 50
      BOX_Y = 50
      TEXT_Y = 105

      # Renders an info diagram to SVG.
      #
      # @param graph [Hash] the info diagram graph structure from transform
      # @return [Svg::Document] the rendered SVG document
      def render(graph)
        scene = typed_scene(graph)
        svg = create_document(scene)

        # Render info box
        render_info_box(scene, svg)

        # Render info text
        render_info_text(scene, svg)

        svg
      end

      protected

      def render_info_box(graph, svg)
        geometry = typed_scene(graph).box
        box = Svg::Rect.new.tap do |r|
          r.x = geometry.x
          r.y = geometry.y
          r.width = geometry.width
          r.height = geometry.height
          r.fill = theme_color(:node_bg) || "#E3F2FD"
          r.stroke = theme_color(:node_stroke) || "#2196F3"
          r.stroke_width = "2"
          r.rx = geometry.corner_radius
          r.ry = geometry.corner_radius
        end

        svg << box
      end

      def render_info_text(graph, svg)
        label = typed_scene(graph).label

        text = Svg::Text.new.tap do |t|
          t.x = label.x
          t.y = label.y
          t.content = label.text
          t.fill = theme_color(:label_text) || "#1976D2"
          t.font_family = theme_typography(:font_family) ||
            "Arial, sans-serif"
          t.font_size = number_string(label.font_size)
          t.text_anchor = label.text_anchor
          t.font_weight = label.font_weight
        end

        svg << text
      end

      def typed_scene(graph)
        return graph if graph.is_a?(Layout::Info::Scene)

        Layout::Info.from_graph(graph, theme: theme)
      end

      def number_string(value)
        value.to_i == value ? value.to_i.to_s : value.to_s
      end
    end
  end
end
