# frozen_string_literal: true

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
    class Kanban
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

      # Metadata display height per item
      METADATA_LINE_HEIGHT = 18

      # Transforms the diagram into a layout structure.
      #
      # @param diagram [Diagram::Kanban] the kanban diagram
      # @return [Hash] layout data with columns, cards, and dimensions
      def to_graph(diagram)
        return empty_graph if diagram.columns.empty?

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
          positioned << {
            id: column.id,
            title: column.title,
            x: current_x,
            y: 0,
            width: COLUMN_WIDTH,
            height: calculate_column_height(column),
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
          current_y = COLUMN_HEADER_HEIGHT + COLUMN_PADDING

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

      # Calculates the height needed for a column
      #
      # @param column [Diagram::KanbanColumn] column
      # @return [Numeric] column height
      def calculate_column_height(column)
        return COLUMN_HEADER_HEIGHT + COLUMN_PADDING if column.cards.empty?

        # Header + padding + sum of card heights + spacing between cards
        total_card_height = column.cards.sum { |card| calculate_card_height(card) }
        total_spacing = (column.cards.size - 1) * CARD_VERTICAL_SPACING
        bottom_padding = COLUMN_PADDING

        COLUMN_HEADER_HEIGHT + COLUMN_PADDING +
          total_card_height + total_spacing + bottom_padding
      end

      # Calculates the height needed for a card
      #
      # @param card [Diagram::KanbanCard] card
      # @return [Numeric] card height
      def calculate_card_height(card)
        base_height = CARD_HEIGHT

        # Add height for metadata if present
        if card.has_metadata?
          metadata_count = card.metadata.size
          base_height + (metadata_count * METADATA_LINE_HEIGHT)
        else
          base_height
        end
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