# frozen_string_literal: true

require_relative "base"
require_relative "../layout/sankey"

module Sirena
  module Renderer
    # Emits SVG from final, typed Sankey geometry.
    class Sankey < Base
      FLOW_COLORS = [
        "#4472C4", # Blue
        "#ED7D31", # Orange
        "#A5A5A5", # Gray
        "#FFC000", # Yellow
        "#5B9BD5", # Light Blue
        "#70AD47", # Green
        "#C00000", # Red
        "#7030A0", # Purple
      ].freeze

      # @param scene [Layout::Sankey::Scene] final canvas geometry
      # @return [Svg::Document] rendered SVG document
      def render(scene)
        svg = create_document(scene)
        render_title(scene.title, svg) if scene.title
        scene.flows.each { |flow| render_flow(flow, svg) unless flow.self_loop }
        scene.nodes.each { |node| render_node(node, svg) }
        svg
      end

      protected

      def render_title(title, svg)
        svg << Svg::Text.new.tap do |text|
          text.x = title.x
          text.y = title.y
          text.content = title.text
          text.fill = theme_color(:label_text) || "#000000"
          text.font_family =
            theme_typography(:font_family) || "Arial, sans-serif"
          text.font_size = (theme_typography(:font_size_large) || 18).to_s
          text.text_anchor = "middle"
          text.font_weight = "bold"
        end
      end

      def render_node(node, svg)
        svg << node_rectangle(node)
        svg << node_label(node.label)
      end

      def node_rectangle(node)
        Svg::Rect.new.tap do |rect|
          rect.x = node.x
          rect.y = node.y
          rect.width = node.width
          rect.height = node.height
          rect.fill = theme_color(:node_fill) || "#2E86AB"
          rect.stroke = theme_color(:node_stroke) || "#1A5276"
          rect.stroke_width = "2"
          rect.rx = node.corner_radius
          rect.ry = node.corner_radius
        end
      end

      def node_label(label)
        Svg::Text.new.tap do |text|
          text.x = label.x
          text.y = label.y
          text.content = label.text
          text.fill = theme_color(:node_text) || "#FFFFFF"
          text.font_family =
            theme_typography(:font_family) || "Arial, sans-serif"
          text.font_size = (theme_typography(:font_size_small) || 11).to_s
          text.text_anchor = "middle"
          text.font_weight = "bold"
        end
      end

      def render_flow(flow, svg)
        svg << Svg::Path.new.tap do |path|
          path.d = flow.path
          path.fill = flow_colour(flow)
          path.opacity = "0.4"
          path.stroke = "none"
        end
        svg << flow_label(flow.label) if flow.label
      end

      def flow_label(label)
        Svg::Text.new.tap do |text|
          text.x = label.x
          text.y = label.y
          text.content = label.text
          text.fill = theme_color(:label_text) || "#333333"
          text.font_family =
            theme_typography(:font_family) || "Arial, sans-serif"
          text.font_size = (theme_typography(:font_size_small) || 10).to_s
          text.text_anchor = "middle"
        end
      end

      def flow_colour(flow)
        FLOW_COLORS.fetch(flow.colour_index % FLOW_COLORS.length)
      end
    end
  end
end
