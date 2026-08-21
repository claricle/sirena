# frozen_string_literal: true

require_relative 'base'
require_relative 'grammars/flowchart'
require_relative 'transforms/flowchart'
require_relative '../diagram/flowchart'

module Sirena
  module Parser
    # Flowchart parser for Mermaid flowchart syntax.
    #
    # Parses flowchart diagrams with support for:
    # - Multiple node shapes (rectangle, rounded, rhombus, circle, etc.)
    # - Multiple edge types (arrow, line, dotted, etc.)
    # - Node labels with special characters
    # - Edge chaining (A --> B --> C)
    # - Subgraphs
    # - Styling directives
    # - Direction specification (TD, LR, etc.)
    #
    # @example Parse a simple flowchart
    #   parser = FlowchartParser.new
    #   diagram = parser.parse("graph TD\nA[Start]-->B[End]")
    class FlowchartParser < Base
      # Parses flowchart source into a Flowchart diagram model.
      #
      # @param source [String] the Mermaid flowchart source
      # @return [Diagram::Flowchart] the parsed flowchart
      # @raise [ParseError] if syntax is invalid
      def parse(source)
        tree = parse_with_grammar(Grammars::Flowchart.new, source)
        Transforms::Flowchart.apply(tree)
      end

      private

      # Formats a Parslet parse error with context.
      #
      # @param cause [Parslet::Cause] the deepest failure
      # @param source [String] the source that failed to parse
      # @return [String] formatted error message
      def format_parse_error(cause, source)
        lines = source.lines("\n")
        line_num, col_num = failure_position(cause, source)

        context = []
        context << "Parse error at line #{line_num}, column #{col_num}:"

        # A failure at EOF sits one line past the source, so there is no line
        # to quote. Say so and still draw the caret rather than emitting a
        # heading with nothing under it.
        context << if line_num.positive? && line_num <= lines.length
                     lines[line_num - 1].chomp("\n")
                   else
                     '(end of input)'
                   end
        context << caret_for(lines[line_num - 1], col_num)

        # Not cause.to_s: it appends parslet's own byte-counted position,
        # which contradicts the character column in the heading above on any
        # line holding a multibyte character.
        context << failure_message(cause)
        context.join("\n")
      rescue StandardError
        # Fallback to simple error message
        "Parse error: #{cause}"
      end
    end
  end
end
