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
        header_x = x + column[:width] / 2

        header_text = Svg::Text.new.tap do |t|
          t.x = header_x
          t.y = y + header_height / 2 + 5
          t.text_anchor = "middle"
          t.fill = "#ffffff"
          t.font_size = (theme_typography(:font_size) || 14).to_s
          t.font_family = theme_typography(:font_family) || "Arial, sans-serif"
          t.font_weight = "bold"
        end

        assign_markdown_text(header_text, MarkdownText.parse_lines(column[:title]), x: header_x, base_font_weight: "bold")

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
        text_x = x + 10
        lines = truncate_runs(MarkdownText.parse_lines(card[:text]), 25)

        text = Svg::Text.new.tap do |t|
          t.x = text_x
          t.y = text_y
          t.fill = theme_color(:text) || "#1f2937"
          t.font_size = (theme_typography(:font_size) || 13).to_s
          t.font_family = theme_typography(:font_family) || "Arial, sans-serif"
        end

        assign_markdown_text(text, lines, x: text_x)

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

      # Assigns a markdown-parsed label onto a `Svg::Text` element.
      #
      # A label with no markup and no hard line break — the overwhelming
      # majority of kanban text — parses down to exactly the original
      # string in one unstyled run. That case keeps setting plain
      # `content`, unchanged from before this feature existed: no `<tspan>`
      # wrapper, same XML shape every existing corpus fixture and the
      # `kanban_integration_spec` REXML `.text` checks already expect. Only
      # a label that actually needs per-run styling or a line break pays
      # for `<tspan>` children.
      #
      # @param text_element [Svg::Text] element to assign onto
      # @param lines [Array<Array<MarkdownText::Run>>] from
      #   `MarkdownText.parse_lines`, already truncated if truncation
      #   applies at this call site
      # @param x [Numeric] the label's horizontal anchor, passed through to
      #   `build_markdown_tspans`
      # @param base_font_weight [String, nil] passed through to
      #   `build_markdown_tspans`
      # @return [void]
      def assign_markdown_text(text_element, lines, x:, base_font_weight: nil)
        if plain_line?(lines)
          text_element.content = lines.first.first&.text.to_s
        else
          text_element.tspans = build_markdown_tspans(lines, x: x, base_font_weight: base_font_weight)
        end
      end

      # True when parsing found no markup and no hard line break: a single
      # line holding at most one run, styled neither bold nor italic.
      #
      # @param lines [Array<Array<MarkdownText::Run>>]
      # @return [Boolean]
      def plain_line?(lines)
        return false unless lines.length == 1

        runs = lines.first
        runs.length <= 1 && runs.none? { |run| run.bold || run.italic }
      end

      # Builds the <tspan> runs for a markdown-parsed label.
      #
      # Every run in a line after the first line continues immediately
      # after the previous run — no `x`/`dy` needed, SVG just keeps
      # advancing horizontally. Only the FIRST run of a line that followed
      # a hard line break needs both: `x` to reset back to the label's left
      # edge (or center, for the anchor="middle" header), and `dy` to move
      # down one line height. The very first line needs neither — it
      # starts at the parent <text> element's own x/y.
      #
      # @param lines [Array<Array<MarkdownText::Run>>] from
      #   `MarkdownText.parse_lines`, already truncated if truncation
      #   applies at this call site
      # @param x [Numeric] the label's horizontal anchor, repeated on every
      #   line-starting run after the first
      # @param base_font_weight [String, nil] "bold" when the surrounding
      #   `Svg::Text` is bold by default (the column header), so a plain
      #   run still renders bold instead of losing the baseline weight
      # @return [Array<Svg::Tspan>]
      def build_markdown_tspans(lines, x:, base_font_weight: nil)
        lines.each_with_index.flat_map do |runs, line_index|
          runs.each_with_index.map do |run, run_index|
            new_line = line_index.positive? && run_index.zero?

            Svg::Tspan.new.tap do |t|
              t.x = x if new_line
              t.dy = "1.2em" if new_line
              t.font_weight = "bold" if run.bold || base_font_weight == "bold"
              t.font_style = "italic" if run.italic
              t.content = run.text
            end
          end
        end
      end

      # Truncates markdown-parsed lines to at most `max_length` visible
      # (post-markup) characters, cutting on run boundaries rather than
      # mid-marker.
      #
      # A run within the FIRST line may be cut partway through, with
      # "..." appended — this is the common case truncation exists for.
      # A later line (one that only exists because of a hard line break)
      # is kept whole or dropped whole, never cut partway through: mirrors
      # how the raw-string truncation this replaces already treated its
      # input as one unit, just applied after parsing instead of before.
      #
      # @param lines [Array<Array<MarkdownText::Run>>]
      # @param max_length [Integer] maximum visible characters to keep
      # @return [Array<Array<MarkdownText::Run>>]
      def truncate_runs(lines, max_length)
        budget = max_length
        result = []

        lines.each_with_index do |runs, line_index|
          line_length = runs.sum { |run| run.text.length }

          if line_length <= budget
            result << runs
            budget -= line_length
            next
          end

          result << truncate_line(runs, budget) if line_index.zero?
          break
        end

        result
      end

      # Cuts a single line's runs to `budget` visible characters, trimming
      # whole runs from the end and appending "..." to the run that
      # crosses the boundary.
      #
      # @param runs [Array<MarkdownText::Run>]
      # @param budget [Integer] visible characters available
      # @return [Array<MarkdownText::Run>]
      def truncate_line(runs, budget)
        remaining = budget
        kept = []

        runs.each do |run|
          if run.text.length <= remaining
            kept << run
            remaining -= run.text.length
          else
            visible = [remaining - 3, 0].max
            kept << run.with(text: "#{run.text[0, visible]}...")
            break
          end
        end

        kept
      end
    end
  end
end