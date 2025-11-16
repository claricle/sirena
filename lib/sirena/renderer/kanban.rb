# frozen_string_literal: true

require_relative "../svg/document"
require_relative "../svg/rect"
require_relative "../svg/text"
require_relative "../svg/group"
require_relative "../svg/line"

module Sirena
  module Renderer
    # Renders a Kanban board layout to SVG.
    #
    # The renderer converts the positioned layout structure from
    # Transform::Kanban into an SVG visualization showing:
    # - Columns with headers
    # - Cards stacked vertically within columns
    # - Card metadata (assigned, ticket, priority, etc.)
    # - Professional kanban board styling
    #
    # @example Render a kanban board
    #   renderer = Renderer::Kanban.new(theme: my_theme)
    #   svg = renderer.render(layout)
    class Kanban < Base
      # Renders the layout structure to SVG.
      #
      # @param layout [Hash] layout data from Transform::Kanban
      # @return [Svg::Document] rendered SVG document
      def render(layout)
        svg = create_document_from_layout(layout)

        # Render columns then cards
        render_columns(layout, svg)
        render_cards(layout, svg)

        svg
      end

      protected

      # Creates an SVG document with dimensions from layout.
      #
      # @param layout [Hash] layout data
      # @return [Svg::Document] new SVG document
      def create_document_from_layout(layout)
        padding = 40

        Svg::Document.new.tap do |doc|
          doc.width = layout[:width] + (padding * 2)
          doc.height = layout[:height] + (padding * 2)
          doc.view_box = "0 0 #{doc.width} #{doc.height}"

          # Add offset for padding
          @offset_x = padding
          @offset_y = padding
        end
      end

      # Renders all columns
      #
      # @param layout [Hash] layout data
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_columns(layout, svg)
        layout[:columns].each do |column|
          render_column(column, svg)
        end
      end

      # Renders a single column with header
      #
      # @param column [Hash] column data
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_column(column, svg)
        x = column[:x] + @offset_x
        y = column[:y] + @offset_y

        # Column background
        column_bg = Svg::Rect.new.tap do |r|
          r.x = x
          r.y = y
          r.width = column[:width]
          r.height = column[:height]
          r.rx = 8
          r.ry = 8
          r.fill = theme_color(:background) || "#f3f4f6"
          r.stroke = theme_color(:border) || "#d1d5db"
          r.stroke_width = "1"
        end

        svg.add_element(column_bg)

        # Column header
        render_column_header(column, x, y, svg)
      end

      # Renders column header
      #
      # @param column [Hash] column data
      # @param x [Numeric] X position
      # @param y [Numeric] Y position
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_column_header(column, x, y, svg)
        header_height = 50

        # Header background
        header_bg = Svg::Rect.new.tap do |r|
          r.x = x
          r.y = y
          r.width = column[:width]
          r.height = header_height
          r.rx = 8
          r.ry = 8
          r.fill = theme_color(:primary) || "#3b82f6"
        end

        svg.add_element(header_bg)

        # Header text
        header_text = Svg::Text.new.tap do |t|
          t.x = x + column[:width] / 2
          t.y = y + header_height / 2 + 5
          t.text_anchor = "middle"
          t.fill = "#ffffff"
          t.font_size = (theme_typography(:font_size) || 14).to_s
          t.font_family = theme_typography(:font_family) || "Arial, sans-serif"
          t.font_weight = "bold"
          t.content = column[:title]
        end

        svg.add_element(header_text)

        # Card count badge (optional)
        if column[:card_count] > 0
          badge_x = x + column[:width] - 25
          badge_y = y + 15

          badge_circle = Svg::Rect.new.tap do |r|
            r.x = badge_x
            r.y = badge_y
            r.width = 20
            r.height = 20
            r.rx = 10
            r.ry = 10
            r.fill = "#ffffff"
            r.opacity = "0.3"
          end

          svg.add_element(badge_circle)

          badge_text = Svg::Text.new.tap do |t|
            t.x = badge_x + 10
            t.y = badge_y + 14
            t.text_anchor = "middle"
            t.fill = "#ffffff"
            t.font_size = "11"
            t.font_weight = "bold"
            t.content = column[:card_count].to_s
          end

          svg.add_element(badge_text)
        end
      end

      # Renders all cards
      #
      # @param layout [Hash] layout data
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_cards(layout, svg)
        layout[:cards].each do |card|
          render_card(card, svg)
        end
      end

      # Renders a single card
      #
      # @param card [Hash] card data
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_card(card, svg)
        x = card[:x] + @offset_x
        y = card[:y] + @offset_y

        # Card background
        card_bg = Svg::Rect.new.tap do |r|
          r.x = x
          r.y = y
          r.width = card[:width]
          r.height = card[:height]
          r.rx = 6
          r.ry = 6
          r.fill = "#ffffff"
          r.stroke = theme_color(:border) || "#d1d5db"
          r.stroke_width = "1"
        end

        svg.add_element(card_bg)

        # Card text
        render_card_text(card, x, y, svg)

        # Metadata if present
        if card[:has_metadata]
          render_card_metadata(card, x, y, svg)
        end
      end

      # Renders card text
      #
      # @param card [Hash] card data
      # @param x [Numeric] X position
      # @param y [Numeric] Y position
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_card_text(card, x, y, svg)
        text_y = y + 25

        text = Svg::Text.new.tap do |t|
          t.x = x + 10
          t.y = text_y
          t.fill = theme_color(:text) || "#1f2937"
          t.font_size = (theme_typography(:font_size) || 13).to_s
          t.font_family = theme_typography(:font_family) || "Arial, sans-serif"
          t.content = truncate_text(card[:text], 25)
        end

        svg.add_element(text)
      end

      # Renders card metadata
      #
      # @param card [Hash] card data
      # @param x [Numeric] X position
      # @param y [Numeric] Y position
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_card_metadata(card, x, y, svg)
        metadata_y = y + 50
        line_height = 18

        card[:metadata].each_with_index do |(key, value), index|
          next if value.nil? || value.to_s.empty?

          current_y = metadata_y + (index * line_height)

          # Metadata label
          label = Svg::Text.new.tap do |t|
            t.x = x + 10
            t.y = current_y
            t.fill = theme_color(:secondary) || "#6b7280"
            t.font_size = "10"
            t.font_family = theme_typography(:font_family) || "Arial, sans-serif"
            t.content = "#{format_metadata_key(key)}:"
          end

          svg.add_element(label)

          # Metadata value
          value_text = Svg::Text.new.tap do |t|
            t.x = x + 70
            t.y = current_y
            t.fill = theme_color(:text) || "#1f2937"
            t.font_size = "10"
            t.font_family = theme_typography(:font_family) || "Arial, sans-serif"
            t.font_weight = "bold"
            t.content = value.to_s
          end

          svg.add_element(value_text)
        end
      end

      # Formats metadata key for display
      #
      # @param key [Symbol, String] metadata key
      # @return [String] formatted key
      def format_metadata_key(key)
        key.to_s.capitalize
      end

      # Truncates text to a maximum length
      #
      # @param text [String] text to truncate
      # @param max_length [Integer] maximum length
      # @return [String] truncated text
      def truncate_text(text, max_length)
        return text if text.length <= max_length

        "#{text[0...max_length - 3]}..."
      end
    end
  end
end