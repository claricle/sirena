# frozen_string_literal: true

require_relative "base"
require_relative "../layout/info"
require_relative "../svg/document"
require_relative "../svg/text"

module Sirena
  module Renderer
    # Emits SVG from final, typed Info geometry.
    #
    # Renders a simple informational message box with centered text.
    #
    # @example Render an info diagram
    #   renderer = Info.new
    #   svg = renderer.render(scene)
    class Info < Base
      # Renders an Info Scene to SVG.
      #
      # @param scene [Layout::Info::Scene] final canvas and label geometry
      # @return [Svg::Document] the rendered SVG document
      def render(scene)
        svg = create_document(scene)

        # Render info text
        render_info_text(scene, svg)

        svg
      end

      protected

      def render_info_text(scene, svg)
        svg << Svg::Text.new.tap do |text|
          set_info_geometry(text, scene.label)
          set_info_style(text, scene.label)
        end
      end

      def set_info_geometry(text, label)
        text.x = label.x
        text.y = label.y
        text.content = label.text
        text.text_anchor = label.text_anchor
      end

      def set_info_style(text, label)
        text.fill = theme_color(:label_text)
        text.font_family = theme_typography(:font_family) || "Arial, sans-serif"
        text.font_size = number_string(label.font_size)
        text.font_weight = label.font_weight
      end

      def number_string(value)
        value.to_i == value ? value.to_i.to_s : value.to_s
      end
    end
  end
end
