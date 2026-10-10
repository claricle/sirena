# frozen_string_literal: true

require_relative "base"
require_relative "../layout/packet"
require_relative "../svg/document"
require_relative "../svg/rect"
require_relative "../svg/text"
require_relative "../svg/line"
require_relative "../svg/group"

module Sirena
  module Renderer
    # Renders a Packet Diagram scene to SVG the way mermaid draws it: one
    # filled block per field segment, its label centred, the start and end
    # bit numbers above it, and the title below the last row.
    #
    # @example Render a packet diagram
    #   renderer = Renderer::Packet.new(theme: my_theme)
    #   svg = renderer.render(layout)
    class Packet < Base
      # Renders the layout structure to SVG.
      #
      # @param layout [Layout::Packet::Scene, Hash] scene or legacy graph
      # @return [Svg::Document] rendered SVG document
      def render(layout)
        scene = typed_scene(layout)
        svg = create_document(scene)
        scene.fields.each { |field| render_typed_field(field, svg) }
        svg << label_element(scene.title) if scene.title
        svg
      end

      protected

      def typed_scene(layout)
        return layout if layout.is_a?(Layout::Packet::Scene)

        Layout::Packet.from_graph(layout, theme: theme)
      end

      def render_typed_field(field, svg)
        svg << field_box(field.box)
        svg << label_element(field.label)
        svg << label_element(field.start_label)
        svg << label_element(field.end_label) if field.end_label
      end

      def field_box(box)
        Svg::Rect.new.tap do |rect|
          rect.x = box.x
          rect.y = box.y
          rect.width = box.width
          rect.height = box.height
          rect.fill = theme_color(:field_background) || "#efefef"
          rect.stroke = theme_color(:field_border) || "#000000"
          rect.stroke_width = "1"
        end
      end

      def label_element(label)
        Svg::Text.new.tap do |text|
          text.x = label.x
          text.y = label.y
          text.text_anchor = label.text_anchor
          text.dominant_baseline = label.dominant_baseline
          text.fill = label_color(label.style)
          text.font_size = number_string(label.font_size)
          text.font_family = theme_typography(:font_family) || "Arial, sans-serif"
          text.content = label.text
        end
      end

      def label_color(style)
        case style
        when "title" then theme_color(:title_text) || "#000000"
        when "start", "end" then theme_color(:label_text) || "#000000"
        else theme_color(:field_text) || "#000000"
        end
      end

      def number_string(value)
        value.to_i == value ? value.to_i.to_s : value.to_s
      end
    end
  end
end
