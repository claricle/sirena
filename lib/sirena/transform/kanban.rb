# frozen_string_literal: true

require_relative 'base'
require_relative "../markdown_text"

module Sirena
  module Transform
    # Transforms a Kanban diagram into a positioned layout structure.
    #
    # The layout algorithm handles:
    # - Columns positioned horizontally
    # - Cards stacked vertically within columns
    # - Proper spacing and sizing
    #
    # @example Transform a kanban board
    #   transform = Transform::Kanban.new
    #   layout = transform.to_graph(diagram)
    class Kanban < Base
      # Horizontal spacing between columns
      COLUMN_HORIZONTAL_SPACING = 60

      # Vertical spacing between cards
      CARD_VERTICAL_SPACING = 15

      # Column dimensions
      COLUMN_WIDTH = 200
      COLUMN_HEADER_HEIGHT = 50
      COLUMN_PADDING = 10

      # Card dimensions
      CARD_HEIGHT = 80
      CARD_PADDING = 10

      # Height of one extra rendered line below a card's first line — a
      # metadata row, or a markdown hard line break in the card text.
      EXTRA_LINE_HEIGHT = 18

      # Transforms the diagram into a layout structure.
      #
      # @param diagram [Diagram::Kanban] the kanban diagram
      # @return [Hash] layout data with columns, cards, and dimensions
      def build_graph(diagram)
        # diagram.columns.nil? is treated as "no columns" here to match
        # Diagram::Kanban#valid?, which accepts nil as equivalent to empty.
        return empty_graph if diagram.columns.nil? || diagram.columns.empty?

        # Position columns horizontally
        positioned_columns = position_columns(diagram.columns)

        # Position cards within each column
        positioned_cards = position_cards(positioned_columns)

        # Calculate overall bounds
        bounds = calculate_bounds(positioned_columns, positioned_cards)

        {
          columns: positioned_columns,
          cards: positioned_cards,
          width: bounds[:width],
          height: bounds[:height]
        }
      end

      private

      def empty_graph
        {
          columns: [],
          cards: [],
          width: 0,
          height: 0
        }
      end

      # Positions columns horizontally
      #
      # @param columns [Array<Diagram::KanbanColumn>] columns to position
      # @return [Array<Hash>] positioned columns
      def position_columns(columns)
        positioned = []
        current_x = 0

        columns.each do |column|
          header_height = calculate_header_height(column)

          positioned << {
            id: column.id,
            title: column.title,
            x: current_x,
            y: 0,
            width: COLUMN_WIDTH,
            height: calculate_column_height(column, header_height),
            header_height: header_height,
            card_count: column.cards.size,
            original: column
          }

          current_x += COLUMN_WIDTH + COLUMN_HORIZONTAL_SPACING
        end

        positioned
      end

      # Positions cards within their columns
      #
      # @param positioned_columns [Array<Hash>] positioned columns
      # @return [Array<Hash>] positioned cards
      def position_cards(positioned_columns)
        cards = []

        positioned_columns.each do |column_data|
          column = column_data[:original]
          column_x = column_data[:x]
          current_y = column_data[:header_height] + COLUMN_PADDING

          column.cards.each do |card|
            card_height = calculate_card_height(card)

            cards << {
              id: card.id,
              text: card.text,
              column_id: column.id,
              x: column_x + COLUMN_PADDING,
              y: current_y,
              width: COLUMN_WIDTH - (COLUMN_PADDING * 2),
              height: card_height,
              metadata: card.metadata,
              has_metadata: card.has_metadata?,
              original: card
            }

            current_y += card_height + CARD_VERTICAL_SPACING
          end
        end

        cards
      end

      # Calculates the header height for a column, growing past
      # `COLUMN_HEADER_HEIGHT` for each hard line break embedded in the
      # column title (from a markdown newline, rendered as an extra
      # `<tspan>` line by Sirena::MarkdownText#parse_lines) — the same
      # `count("\n")` approach `calculate_card_height` already uses for
      # card text, for the same reason: this layer only needs how many
      # extra lines there are, not what's on them.
      #
      # @param column [Diagram::KanbanColumn] column
      # @return [Numeric] header height
      def calculate_header_height(column)
        COLUMN_HEADER_HEIGHT + (column.title.to_s.count("\n") * EXTRA_LINE_HEIGHT)
      end

      # Calculates the height needed for a column
      #
      # @param column [Diagram::KanbanColumn] column
      # @param header_height [Numeric] this column's own header height, from
      #   `calculate_header_height`
      # @return [Numeric] column height
      def calculate_column_height(column, header_height)
        return header_height + COLUMN_PADDING if column.cards.empty?

        # Header + padding + sum of card heights + spacing between cards
        total_card_height = column.cards.sum { |card| calculate_card_height(card) }
        total_spacing = (column.cards.size - 1) * CARD_VERTICAL_SPACING
        bottom_padding = COLUMN_PADDING

        header_height + COLUMN_PADDING +
          total_card_height + total_spacing + bottom_padding
      end

      # Calculates the height needed for a card
      #
      # Grows for metadata rows and extra rendered lines in the card's own
      # text. Line count must come from `rendered_line_count` (mirrors
      # `Renderer::Kanban#render_card_text`'s own parse+truncate), never a
      # raw `text.count("\n")` — once text crosses
      # `Sirena::MarkdownText::CARD_TEXT_CHAR_BUDGET` the renderer drops
      # whole lines, so a raw count sizes for lines that never render.
      # Reuses EXTRA_LINE_HEIGHT, not a second constant, for the card's own
      # font size (13px * 1.2em/line): Transform has no renderer font size
      # to base one on.
      #
      # @param card [Diagram::KanbanCard] card
      # @return [Numeric] card height
      def calculate_card_height(card)
        base_height = CARD_HEIGHT
        base_height += card.metadata.size * EXTRA_LINE_HEIGHT if card.has_metadata?
        base_height += (rendered_line_count(card.text) - 1) * EXTRA_LINE_HEIGHT
        base_height
      end

      # The number of lines `card.text` actually renders as, after the same
      # markdown parsing and character-budget truncation
      # `Renderer::Kanban#render_card_text` applies. Always at least 1: an
      # empty or all-dropped body still occupies the card's first line, the
      # same as `count("\n") == 0` did before this method replaced it.
      #
      # @param text [String, nil]
      # @return [Integer]
      # @api private
      def rendered_line_count(text)
        lines = Sirena::MarkdownText.truncate_runs(
          Sirena::MarkdownText.parse_lines(text),
          Sirena::MarkdownText::CARD_TEXT_CHAR_BUDGET
        )
        [lines.length, 1].max
      end

      # Calculates the bounding box for the entire board
      #
      # @param columns [Array<Hash>] positioned columns
      # @param cards [Array<Hash>] positioned cards
      # @return [Hash] width and height
      def calculate_bounds(columns, cards)
        return { width: 0, height: 0 } if columns.empty?

        max_x = columns.map { |c| c[:x] + c[:width] }.max
        max_y = columns.map { |c| c[:height] }.max

        {
          width: max_x,
          height: max_y
        }
      end
    end
  end
end