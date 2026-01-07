# frozen_string_literal: true

require "lutaml/model"
require_relative "base"

module Sirena
  module Diagram
    # Represents a card in a Kanban column.
    #
    # A card has an id, text content, and optional metadata like
    # assigned user, ticket number, icon, priority, etc.
    class KanbanCard < Lutaml::Model::Serializable
      # Card identifier
      attribute :id, :string

      # Card text content
      attribute :text, :string

      # Optional metadata
      attribute :assigned, :string
      attribute :ticket, :string
      attribute :icon, :string
      attribute :label, :string
      attribute :priority, :string

      # Validates the card has required fields.
      #
      # @return [Boolean] true if card is valid
      def valid?
        !id.nil? && !id.empty? && !text.nil? && !text.empty?
      end

      # Returns all metadata as a hash.
      #
      # @return [Hash] metadata hash
      def metadata
        {
          assigned: assigned,
          ticket: ticket,
          icon: icon,
          label: label,
          priority: priority
        }.compact
      end

      # Checks if card has any metadata.
      #
      # @return [Boolean] true if card has metadata
      def has_metadata?
        !metadata.empty?
      end
    end

    # Represents a column in a Kanban board.
    #
    # A column has an id, title, and contains multiple cards.
    class KanbanColumn < Lutaml::Model::Serializable
      # Column identifier
      attribute :id, :string

      # Column title/name
      attribute :title, :string

      # Collection of cards in this column
      attribute :cards, KanbanCard, collection: true, default: -> { [] }

      # Validates the column has required fields.
      #
      # @return [Boolean] true if column is valid
      def valid?
        !id.nil? && !id.empty? &&
          !title.nil? && !title.empty? &&
          cards.all?(&:valid?)
      end

      # Adds a card to this column.
      #
      # @param card [KanbanCard] the card to add
      # @return [void]
      def add_card(card)
        cards << card
      end
    end

    # Kanban board diagram model.
    #
    # Represents a complete Kanban board with columns and cards
    # for workflow visualization.
    #
    # @example Creating a simple kanban board
    #   diagram = Kanban.new
    #   column = KanbanColumn.new.tap do |c|
    #     c.id = "todo"
    #     c.title = "Todo"
    #   end
    #   card = KanbanCard.new.tap do |c|
    #     c.id = "docs"
    #     c.text = "Create Documentation"
    #     c.priority = "High"
    #   end
    #   column.add_card(card)
    #   diagram.add_column(column)
    class Kanban < Base
      # Collection of columns in the board
      attribute :columns, KanbanColumn, collection: true,
                                        default: -> { [] }

      # Returns the diagram type identifier.
      #
      # @return [Symbol] :kanban
      def diagram_type
        :kanban
      end

      # Validates the kanban board structure.
      #
      # A kanban is valid if:
      # - It has at least one column
      # - All columns are valid
      # - All cards within columns are valid
      #
      # @return [Boolean] true if kanban board is valid
      def valid?
        return false if columns.nil? || columns.empty?
        return false unless columns.all?(&:valid?)

        true
      end

      # Adds a column to the board.
      #
      # @param column [KanbanColumn] the column to add
      # @return [void]
      def add_column(column)
        columns << column
      end

      # Returns all cards across all columns.
      #
      # @return [Array<KanbanCard>] all cards in the board
      def all_cards
        columns.flat_map(&:cards)
      end

      # Finds a column by id.
      #
      # @param id [String] the column id
      # @return [KanbanColumn, nil] the column or nil if not found
      def find_column(id)
        columns.find { |c| c.id == id }
      end

      # Finds cards by assigned user.
      #
      # @param user [String] the assigned user
      # @return [Array<KanbanCard>] cards assigned to the user
      def cards_by_assigned(user)
        all_cards.select { |c| c.assigned == user }
      end

      # Finds cards by priority.
      #
      # @param priority [String] the priority level
      # @return [Array<KanbanCard>] cards with the given priority
      def cards_by_priority(priority)
        all_cards.select { |c| c.priority == priority }
      end

      # Finds cards by ticket.
      #
      # @param ticket [String] the ticket number
      # @return [Array<KanbanCard>] cards with the given ticket
      def cards_by_ticket(ticket)
        all_cards.select { |c| c.ticket == ticket }
      end
    end
  end
end