# frozen_string_literal: true

require_relative 'base'
require_relative 'grammars/block'
require_relative 'transforms/block'
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
    #   parser = BlockParser.new
    #   diagram = parser.parse("block-beta\n  columns 2\n  A\n  B")
    class BlockParser < Base
      # Parses block diagram source into a BlockDiagram model.
      #
      # @param source [String] the Mermaid block diagram source
      # @return [Diagram::BlockDiagram] the parsed block diagram
      # @raise [ParseError] if syntax is invalid
      def parse(source)
        grammar = Grammars::Block.new

        begin
          tree = grammar.parse(source)
          diagram = Transforms::Block.apply(tree)
          diagram
        rescue Parslet::ParseFailed => e
          raise ParseError, format_parse_error(e, source)
        end
      end

      private

      # Formats a Parslet parse error with context.
      #
      # @param error [Parslet::ParseFailed] the parse error
      # @param source [String] the source that failed to parse
      # @return [String] formatted error message
      def format_parse_error(error, source)
        lines = source.lines
        line_num = error.parse_failure_cause.source.line_and_column[0]
        col_num = error.parse_failure_cause.source.line_and_column[1]

        context = []
        context << "Parse error at line #{line_num}, column #{col_num}:"

        # Show the problematic line
        if line_num > 0 && line_num <= lines.length
          context << lines[line_num - 1].chomp
          context << (' ' * (col_num - 1)) + '^'
        end

        context << error.parse_failure_cause.to_s
        context.join("\n")
      rescue StandardError
        # Fallback to simple error message
        "Parse error: #{error.message}"
      end
    end
  end
end