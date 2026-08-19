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
        tree = parse_with_grammar(Grammars::Block.new, source)
        Transforms::Block.apply(tree)
      end

      private

      # Formats a Parslet parse error with context.
      #
      # @param error [Parslet::ParseFailed] the parse error
      # @param source [String] the source that failed to parse
      # @return [String] formatted error message
      def format_parse_error(cause, source)
        lines = source.lines
        line_num, col_num = failure_position(cause, source)

        context = []
        context << "Parse error at line #{line_num}, column #{col_num}:"

        # A failure at EOF sits one line past the source, so there is no line
        # to quote. Say so and still draw the caret rather than emitting a
        # heading with nothing under it.
        context << if line_num.positive? && line_num <= lines.length
                     lines[line_num - 1].chomp
                   else
                     '(end of input)'
                   end
        context << (' ' * (col_num - 1)) + '^'

        # cause.message, not cause.to_s: the latter appends parslet's own
        # byte-counted position, which contradicts the character column in
        # the heading above on any line holding a multibyte character.
        context << cause.message
        context.join("\n")
      rescue StandardError
        # Fallback to simple error message
        "Parse error: #{cause.message}"
      end
    end
  end
end