# frozen_string_literal: true

require_relative 'base'
require_relative 'grammars/quadrant'
require_relative 'transforms/quadrant'
require_relative '../diagram/quadrant'

module Sirena
  module Parser
    # Quadrant chart parser for Mermaid quadrant diagram syntax.
    #
    # Uses Parslet grammar-based parsing to handle quadrant chart syntax
    # with axis labels, quadrant labels, and data points.
    #
    # Parses quadrant charts with support for:
    # - Title declarations
    # - X-axis and Y-axis labels
    # - Quadrant labels (1-4)
    # - Data points with normalized coordinates
    # - Point styling (radius, color, stroke)
    # - Comments
    #
    # @example Parse a simple quadrant chart
    #   parser = QuadrantParser.new
    #   source = <<~MERMAID
    #     quadrantChart
    #       title Product Analysis
    #       x-axis Low Cost --> High Cost
    #       y-axis Low Value --> High Value
    #       Product A: [0.3, 0.7]
    #   MERMAID
    #   diagram = parser.parse(source)
    class QuadrantParser < Base
      # Parses quadrant chart diagram source into a QuadrantChart model.
      #
      # @param source [String] the Mermaid quadrant chart diagram source
      # @return [Diagram::QuadrantChart] the parsed quadrant chart diagram
      # @raise [ParseError] if syntax is invalid
      def parse(source)
        grammar = Grammars::Quadrant.new

        begin
          parse_tree = grammar.parse(source)
        rescue Parslet::ParseFailed => e
          raise ParseError, "Syntax error at #{e.parse_failure_cause.pos}: " \
                           "#{e.parse_failure_cause}"
        end

        # Transform parse tree to diagram model
        transform = Transforms::Quadrant.new
        diagram = transform.apply(parse_tree)

        diagram
      end
    end
  end
end