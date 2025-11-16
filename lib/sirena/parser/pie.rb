# frozen_string_literal: true

require_relative 'base'
require_relative 'grammars/pie'
require_relative 'transforms/pie'
require_relative '../diagram/pie'

module Sirena
  module Parser
    # Pie chart parser for Mermaid pie diagram syntax.
    #
    # Uses Parslet grammar-based parsing to handle pie chart syntax
    # with labeled data entries and numeric values.
    #
    # Parses pie charts with support for:
    # - Title declarations
    # - showData flag for displaying values
    # - Data entries with quoted labels and numeric values
    # - Accessibility features (accTitle, accDescr)
    # - Comments
    #
    # @example Parse a simple pie chart
    #   parser = PieParser.new
    #   diagram = parser.parse("pie\n  \"Apples\" : 42\n  \"Oranges\" : 58")
    class PieParser < Base
      # Parses pie chart diagram source into a Pie diagram model.
      #
      # @param source [String] the Mermaid pie chart diagram source
      # @return [Diagram::Pie] the parsed pie chart diagram
      # @raise [ParseError] if syntax is invalid
      def parse(source)
        grammar = Grammars::Pie.new

        begin
          parse_tree = grammar.parse(source)
        rescue Parslet::ParseFailed => e
          raise ParseError, "Syntax error at #{e.parse_failure_cause.pos}: " \
                           "#{e.parse_failure_cause}"
        end

        # Transform parse tree to diagram model
        transform = Transforms::Pie.new
        diagram = transform.apply(parse_tree)

        diagram
      end
    end
  end
end