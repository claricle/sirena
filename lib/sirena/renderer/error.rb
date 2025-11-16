# frozen_string_literal: true

require_relative 'base'
require_relative '../svg/document'
require_relative '../svg/rect'
require_relative '../svg/text'
require_relative '../svg/circle'
require_relative '../svg/path'

module Sirena
  module Renderer
    # Error diagram renderer for converting error diagrams to SVG.
    #
    # Renders an error message box with a warning icon and error text.
    #
    # @example Render an error diagram
    #   renderer = ErrorRenderer.new
    #   svg = renderer.render(error_diagram)
    class ErrorRenderer < Base
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
        svg = create_document_for_error(graph)

        # Render error box
        render_error_box(graph, svg)

        # Render error icon
        render_error_icon(svg)

        # Render error text
        render_error_text(graph, svg)

        svg
      end

      protected

      def create_document_for_error(_graph)
        width = 500
        height = 220

        Svg::Document.new.tap do |doc|
          doc.width = width
          doc.height = height
          doc.view_box = "0 0 #{width} #{height}"
        end
      end

      def render_error_box(_graph, svg)
        box = Svg::Rect.new.tap do |r|
          r.x = BOX_X
          r.y = BOX_Y
          r.width = BOX_WIDTH
          r.height = BOX_HEIGHT
          r.fill = '#FFEBEE'
          r.stroke = '#D32F2F'
          r.stroke_width = '2'
          r.rx = '8'
          r.ry = '8'
        end

        svg << box
      end

      def render_error_icon(svg)
        # Error icon circle
        circle = Svg::Circle.new.tap do |c|
          c.cx = ICON_CENTER_X
          c.cy = ICON_CENTER_Y
          c.r = ICON_RADIUS
          c.fill = '#D32F2F'
          c.stroke = '#B71C1C'
          c.stroke_width = '2'
        end
        svg << circle

        # Exclamation mark - vertical line
        line = Svg::Rect.new.tap do |r|
          r.x = ICON_CENTER_X - 2
          r.y = ICON_CENTER_Y - 10
          r.width = 4
          r.height = 12
          r.fill = '#FFFFFF'
          r.rx = '2'
        end
        svg << line

        # Exclamation mark - dot
        dot = Svg::Circle.new.tap do |c|
          c.cx = ICON_CENTER_X
          c.cy = ICON_CENTER_Y + 6
          c.r = 2
          c.fill = '#FFFFFF'
        end
        svg << dot
      end

      def render_error_text(graph, svg)
        message = graph[:message] || 'Error'

        text = Svg::Text.new.tap do |t|
          t.x = TEXT_X
          t.y = TEXT_Y
          t.content = message
          t.fill = '#C62828'
          t.font_family = theme_typography(:font_family) ||
                          'Arial, sans-serif'
          t.font_size = (theme_typography(:font_size_base) || 16).to_s
          t.text_anchor = 'start'
          t.font_weight = 'bold'
        end

        svg << text
      end
    end
  end
end