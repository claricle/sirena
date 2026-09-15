# frozen_string_literal: true

require_relative "../svg/document"
require_relative "../svg/rect"
require_relative "../svg/text"
require_relative "../svg/group"
require_relative "../svg/line"
require_relative "markdown_text"

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
      # Height of one extra rendered line — a card's own hard line break, or
      # a metadata row. Mirrors Transform::Kanban::EXTRA_LINE_HEIGHT: this
      # renderer positions elements below a label whose height that constant
      # already accounts for, so the two must agree.
      EXTRA_LINE_HEIGHT = 18
      private_constant :EXTRA_LINE_HEIGHT

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
        header_height = column[:header_height]

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
        header_x = x + column[:width] / 2
        lines = MarkdownText.parse_lines(column[:title])
        font_size = theme_typography(:font_size) || 14

        header_text = Svg::Text.new.tap do |t|
          t.x = header_x
          t.y = header_text_baseline(y, header_height, lines.length, font_size)
          t.text_anchor = "middle"
          t.fill = "#ffffff"
          t.font_size = font_size.to_s
          t.font_family = theme_typography(:font_family) || "Arial, sans-serif"
          t.font_weight = "bold"
        end

        MarkdownText.assign_markdown_text(header_text, lines, x: header_x, base_font_weight: "bold")

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

      # Codex round 6 High: this used to be a flat `y + header_height / 2 +
      # 5`, which only centers correctly for a SINGLE line of text — every
      # line past the first advances by a further `1.2em` below that fixed
      # point (`assign_markdown_text`'s per-line `dy`), so a multi-line
      # title's later lines kept sliding further past the header rect's own
      # bottom edge the more lines it had. Reproduced directly via the real
      # CLI + REXML: a 4-line title (`col[One\nTwo\nThree\nFour]`) sized a
      # `header_height` of 104 (`Transform::Kanban::COLUMN_HEADER_HEIGHT`
      # 50 plus 3 `Transform::Kanban::EXTRA_LINE_HEIGHT` (18) rows), but the
      # 4th baseline landed at `147.4` — `3.4px` past the header rect's own
      # bottom edge at `144`.
      #
      # Fixed by centering the whole text BLOCK rather than a single
      # baseline: `+ 5` alone is the single-line fudge already tuned to
      # visually center one baseline within `header_height` (unchanged for
      # `line_count == 1`, so no regression there), and each additional
      # line adds one more `1.2em` (`font_size * 1.2`, the same per-line
      # advance `assign_markdown_text` actually renders — not a raw
      # `count("\n")`, per the same "size from the renderer's own line
      # count, not the raw text" fix already applied to
      # `Transform::Kanban#calculate_card_height`) to the block's total
      # height; shifting the FIRST baseline up by half of that added height
      # keeps the block centered around the same point the single-line
      # formula already centers on. Verified directly (real
      # `Renderer::Kanban#render` + REXML) for the 4-line case above: first
      # baseline moves from the old `97.0` to `71.8`, last baseline from the
      # overflowing `147.4` to `122.2` — comfortably inside the header
      # rect's bottom edge at `144.0` (`y=40.0` plus `header_height=104.0`),
      # with room to spare on the top edge too.
      #
      # @param y [Numeric] the header rect's own top edge
      # @param header_height [Numeric] the header rect's own height, from
      #   `Transform::Kanban#calculate_header_height`
      # @param line_count [Integer] number of lines `MarkdownText.parse_lines`
      #   actually produced for this title
      # @param font_size [Numeric] the header text's own font size, in px
      # @return [Numeric] the first line's baseline `y`
      # @api private
      def header_text_baseline(y, header_height, line_count, font_size)
        line_height = font_size * 1.2
        y + (header_height / 2) + 5 - ((line_count - 1) * line_height / 2)
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
        label_line_count = render_card_text(card, x, y, svg)

        # Metadata if present
        if card[:has_metadata]
          render_card_metadata(card, x, y, label_line_count, svg)
        end
      end

      # Renders card text
      #
      # @param card [Hash] card data
      # @param x [Numeric] X position
      # @param y [Numeric] Y position
      # @param svg [Svg::Document] SVG document
      # @return [Integer] number of lines the label actually rendered, after
      #   markdown parsing and truncation — what `render_card_metadata` needs
      #   to start below the label rather than at a fixed offset
      def render_card_text(card, x, y, svg)
        text_y = y + 25
        text_x = x + 10
        lines = MarkdownText.truncate_runs(MarkdownText.parse_lines(card[:text]), MarkdownText::CARD_TEXT_CHAR_BUDGET)

        text = Svg::Text.new.tap do |t|
          t.x = text_x
          t.y = text_y
          t.fill = theme_color(:text) || "#1f2937"
          t.font_size = (theme_typography(:font_size) || 13).to_s
          t.font_family = theme_typography(:font_family) || "Arial, sans-serif"
        end

        MarkdownText.assign_markdown_text(text, lines, x: text_x)

        svg.add_element(text)

        lines.length
      end

      # Renders card metadata
      #
      # @param card [Hash] card data
      # @param x [Numeric] X position
      # @param y [Numeric] Y position
      # @param label_line_count [Integer] lines the card's own label actually
      #   rendered, from `render_card_text` — metadata starts below all of
      #   them rather than at the single-line offset a multi-line label would
      #   overlap
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_card_metadata(card, x, y, label_line_count, svg)
        extra_label_lines = [label_line_count - 1, 0].max
        metadata_y = y + 50 + (extra_label_lines * EXTRA_LINE_HEIGHT)
        line_height = EXTRA_LINE_HEIGHT

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
    end
  end
end