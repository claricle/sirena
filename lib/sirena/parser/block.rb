# frozen_string_literal: true

require_relative 'base'
require_relative 'grammars/block'
require_relative 'builders/block'
require_relative '../diagram/block'

module Sirena
  module Parser
    # Block diagram parser for Mermaid block diagram syntax.
    #
    # Parses block diagrams with support for:
    # - Column-based layouts
    # - Blocks with various shapes (rectangle, circle)
    # - Block width specifications
    # - Compound/nested blocks
    # - Space placeholders
    # - Arrow blocks with directions
    # - Connections between blocks
    # - Styling directives
    #
    # @example Parse a simple block diagram
    #   parser = Block.new
    #   diagram = parser.parse("block-beta\n  columns 2\n  A\n  B")
    class Block < Base
      # Parses block diagram source into a Block model.
      #
      # @param source [String] the Mermaid block diagram source
      # @return [Diagram::Block] the parsed block diagram
      # @raise [ParseError] if syntax is invalid
      def parse(source)
        tree = parse_with_grammar(Grammars::Block.new, source)
        Builders::Block.apply(tree)
      end

      private

      # Formats a Parslet parse error with context.
      #
      # @param cause [Parslet::Cause] the deepest failure
      # @param source [String] the source that failed to parse
      # @return [String] formatted error message
      def format_parse_error(cause, source)
        format_parse_error_guarded(cause, source)
      end
    end
  end
end