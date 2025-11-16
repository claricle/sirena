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
        grammar = Grammars::Flowchart.new

        begin
          tree = grammar.parse(source)
          diagram = Transforms::Flowchart.apply(tree)
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
