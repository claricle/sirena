# frozen_string_literal: true

require_relative "base"
require_relative "grammars/kanban"
require_relative "builders/kanban"
require_relative "../diagram/kanban"

module Sirena
  module Parser
    # Kanban parser for Mermaid kanban diagram syntax.
    #
    # Uses Parslet grammar-based parsing to handle kanban syntax
    # with columns, cards, and metadata.
    #
    # Parses kanban boards with support for:
    # - Column definitions: id[Title], or a bare id
    # - Card definitions: id[Text], or a bare id
    # - Metadata: @{ key: 'value' }, with or without a bracket label
    # - Properties: assigned, ticket, icon, label, priority
    #
    # @example Parse a simple kanban board
    #   parser = Kanban.new
    #   source = <<~MERMAID
    #     kanban
    #       id1[Todo]
    #         docs[Create Documentation]
    #       id2[Done]
    #         release[Release v1.0]
    #   MERMAID
    #   diagram = parser.parse(source)
    class Kanban < Base
      grammar Grammars::Kanban
      builder Builders::Kanban

      # Parses kanban diagram source into a Kanban model.
      #
      # @param source [String] the Mermaid kanban diagram source
      # @return [Diagram::Kanban] the parsed kanban diagram
      # @raise [ParseError] if syntax is invalid
      # @raise [ArgumentError] if source is not a String
      def parse(source)
        unless source.is_a?(String)
          raise ArgumentError,
                "kanban source must be a String, got #{source.class}"
        end

        super(readable_source(source))
      end

      private

      def readable_source(source)
        normalize_line_ends(transcode_to_utf8(source))
      end

      # The grammar and builder regexps carry non-ASCII (`\u`) classes, so
      # matching them against a binary or ISO-8859-1 string raises
      # Encoding::CompatibilityError instead of a parse result. A UTF-8 string
      # with invalid bytes is re-encoded too: Parslet raises ArgumentError on
      # it. A binary or US-ASCII string holds the bytes of a file read as
      # UTF-8, so it is retagged, as `Source.split` does, not transcoded.
      def transcode_to_utf8(source)
        if [Encoding::BINARY, Encoding::US_ASCII].include?(source.encoding)
          return source.dup.force_encoding(Encoding::UTF_8).scrub
        end

        recoded = source.encode(Encoding::UTF_8,
                                invalid: :replace, undef: :replace)
        recoded.b.force_encoding(Encoding::UTF_8).scrub
      rescue Encoding::ConverterNotFoundError
        raise ParseError,
              "Cannot read a #{source.encoding} source: " \
              "it has no UTF-8 converter."
      end

      # mermaid folds a CRLF and a lone CR into a newline before it lexes
      # anything, so a bare `\r` ends a line and a comment. The grammar's
      # `newline` knows `\n` and `\r\n` only.
      def normalize_line_ends(source)
        source.gsub(/\r\n?/, "\n")
      end

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
          title: column_data[:title],
          icon: column_data[:icon],
          # No `|| []` fallback here: BoardBuilder#normalize_classes already
          # guarantees an Array, so `column_data[:classes]` is never nil.
          classes: column_data[:classes],
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
          priority: card_data[:priority],
          # No `|| []` fallback here either: BoardBuilder#add_card always
          # merges a normalize_classes result, so this is never nil either.
          classes: card_data[:classes],
        )
      end
    end
  end
end
