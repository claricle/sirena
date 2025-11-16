# frozen_string_literal: true

require_relative 'base'
require_relative '../svg/document'
require_relative '../svg/rect'
require_relative '../svg/text'

module Sirena
  module Renderer
    # Info diagram renderer for converting info diagrams to SVG.
    #
    # Renders a simple informational message box with centered text.
    #
    # @example Render an info diagram
    #   renderer = InfoRenderer.new
    #   svg = renderer.render(info_diagram)
    class InfoRenderer < Base
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
        svg = create_document_for_info(graph)

        # Render info box
        render_info_box(graph, svg)

        # Render info text
        render_info_text(graph, svg)

        svg
      end

      protected

      def create_document_for_info(_graph)
        width = 500
        height = 200

        Svg::Document.new.tap do |doc|
          doc.width = width
          doc.height = height
          doc.view_box = "0 0 #{width} #{height}"
        end
      end

      def render_info_box(_graph, svg)
        box = Svg::Rect.new.tap do |r|
          r.x = BOX_X
          r.y = BOX_Y
          r.width = BOX_WIDTH
          r.height = BOX_HEIGHT
          r.fill = theme_color(:node_bg) || '#E3F2FD'
          r.stroke = theme_color(:node_stroke) || '#2196F3'
          r.stroke_width = '2'
          r.rx = '8'
          r.ry = '8'
        end

        svg << box
      end

      def render_info_text(graph, svg)
        message = if graph[:show_info]
                    'Info: showInfo enabled'
                  else
                    'Info'
                  end

        text = Svg::Text.new.tap do |t|
          t.x = BOX_X + (BOX_WIDTH / 2)
          t.y = TEXT_Y
          t.content = message
          t.fill = theme_color(:label_text) || '#1976D2'
          t.font_family = theme_typography(:font_family) ||
                          'Arial, sans-serif'
          t.font_size = (theme_typography(:font_size_base) || 16).to_s
          t.text_anchor = 'middle'
          t.font_weight = 'bold'
        end

        svg << text
      end
    end
  end
end