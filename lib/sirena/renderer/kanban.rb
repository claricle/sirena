# frozen_string_literal: true

require_relative "base"
require_relative "../layout/kanban"
require_relative "../svg/document"
require_relative "../svg/rect"
require_relative "../svg/text"
require_relative "markdown_text"

module Sirena
  module Renderer
    # Emits SVG from final, typed Kanban geometry.
    class Kanban < Base
      # @param scene [Layout::Kanban::Scene, Hash] final geometry or released
      #   positioned-Hash input
      # @return [Svg::Document] rendered SVG document
      def render(scene)
        unless scene.is_a?(Layout::Kanban::Scene)
          scene = Layout::Kanban.from_graph(scene, theme: theme)
        end
        svg = create_document(scene)
        scene.columns.each { |column| render_column(column, svg) }
        scene.cards.each { |card| render_card(card, svg) }
        svg
      end

      protected

      def render_column(column, svg)
        svg << box_element(column.background)
        svg << box_element(column.header)
        svg << label_element(column.title)
        return unless column.badge

        svg << box_element(column.badge)
        svg << label_element(column.badge_label)
      end

      def render_card(card, svg)
        svg << box_element(card.background)
        svg << label_element(card.label)
        card.metadata.each { |label| svg << label_element(label) }
      end

      def box_element(box)
        Svg::Rect.new.tap do |rect|
          rect.x = box.x
          rect.y = box.y
          rect.width = box.width
          rect.height = box.height
          rect.rx = box.corner_radius
          rect.ry = box.corner_radius
          apply_box_style(rect, box.style)
        end
      end

      def apply_box_style(rect, style)
        case style
        when "column"
          rect.fill = theme_color(:background) || "#f3f4f6"
          rect.stroke = theme_color(:border) || "#d1d5db"
          rect.stroke_width = "1"
        when "header"
          rect.fill = theme_color(:primary) || "#3b82f6"
        when "badge"
          rect.fill = "#ffffff"
          rect.opacity = "0.3"
        when "card"
          rect.fill = "#ffffff"
          rect.stroke = theme_color(:border) || "#d1d5db"
          rect.stroke_width = "1"
        end
      end

      def label_element(label)
        Svg::Text.new.tap do |text|
          text.x = label.x
          text.y = label.y
          text.fill = label_color(label.style)
          text.font_size = number_string(label.font_size)
          text.font_family =
            theme_typography(:font_family) || "Arial, sans-serif"
          text.text_anchor = label.text_anchor if label.text_anchor
          text.font_weight = label.font_weight if label.font_weight
          assign_content(text, label)
        end
      end

      def assign_content(text, label)
        if label.style == "header"
          MarkdownText.assign_markdown_text(
            text, Sirena::MarkdownText.parse_lines(label.text),
            x: label.x, base_font_weight: "bold"
          )
        elsif label.style == "card"
          lines = Sirena::MarkdownText.truncate_runs(
            Sirena::MarkdownText.parse_lines(label.text),
            Sirena::MarkdownText::CARD_TEXT_CHAR_BUDGET,
          )
          MarkdownText.assign_markdown_text(text, lines, x: label.x)
        else
          text.content = label.text
        end
      end

      def label_color(style)
        case style
        when "header", "badge" then "#ffffff"
        when "metadata_label" then theme_color(:secondary) || "#6b7280"
        else theme_color(:text) || "#1f2937"
        end
      end

      def number_string(value)
        value.to_i == value ? value.to_i.to_s : value.to_s
      end
    end
  end
end
