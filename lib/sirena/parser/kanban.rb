# frozen_string_literal: true

require_relative "base"
require_relative "grammars/kanban"
require_relative "transforms/kanban"
require_relative "../diagram/kanban"

module Sirena
  module Parser
    # Kanban parser for Mermaid kanban diagram syntax.
    #
    # Uses Parslet grammar-based parsing to handle kanban syntax
    # with columns, cards, and metadata.
    #
    # Parses kanban boards with support for:
    # - Column definitions: id[Title]
    # - Card definitions: id[Text]
    # - Metadata: @{ key: 'value' }
    # - Properties: assigned, ticket, icon, label, priority
    #
    # @example Parse a simple kanban board
    #   parser = KanbanParser.new
    #   source = <<~MERMAID
    #     kanban
    #       id1[Todo]
    #         docs[Create Documentation]
    #       id2[Done]
    #         release[Release v1.0]
    #   MERMAID
    #   diagram = parser.parse(source)
    class KanbanParser < Base
      # Parses kanban diagram source into a Kanban model.
      #
      # @param source [String] the Mermaid kanban diagram source
      # @return [Diagram::Kanban] the parsed kanban diagram
      # @raise [ParseError] if syntax is invalid
      def parse(source)
        grammar = Grammars::Kanban.new

        begin
          parse_tree = grammar.parse(source)
        rescue Parslet::ParseFailed => e
          raise ParseError, "Syntax error at #{e.parse_failure_cause.pos}: " \
                           "#{e.parse_failure_cause}"
        end

        # Transform parse tree to diagram model
        transform = Transforms::Kanban.new
        result = transform.apply(parse_tree)

        # Create the diagram model
        create_diagram(result)
      end

      private

      def create_diagram(result)
        diagram = Diagram::Kanban.new

        # Build columns and cards
        result[:columns]&.each do |column_data|
          column = build_column(column_data)
          diagram.add_column(column)
        end

        diagram
      end

      def build_column(column_data)
        column = Diagram::KanbanColumn.new(
          id: column_data[:id],
          title: column_data[:title]
        )

        # Add cards to column
        column_data[:cards]&.each do |card_data|
          card = build_card(card_data)
          column.add_card(card)
        end

        column
      end

      def build_card(card_data)
        Diagram::KanbanCard.new(
          id: card_data[:id],
          text: card_data[:text],
          assigned: card_data[:assigned],
          ticket: card_data[:ticket],
          icon: card_data[:icon],
          label: card_data[:label],
          priority: card_data[:priority]
        )
      end
    end
  end
end