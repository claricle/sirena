# frozen_string_literal: true

require_relative 'base'
require_relative 'grammars/error'
require_relative 'transforms/error'
require_relative '../diagram/error'

module Sirena
  module Parser
    # Error diagram parser for Mermaid error diagram syntax.
    #
    # Uses Parslet grammar-based parsing to handle simple error diagrams.
    #
    # Parses error diagrams with support for:
    # - Basic error keyword
    # - Optional error message text
    #
    # @example Parse a simple error diagram
    #   parser = ErrorParser.new
    #   diagram = parser.parse("error")
    #
    # @example Parse error diagram with message
    #   parser = ErrorParser.new
    #   diagram = parser.parse("Error Diagrams")
    class ErrorParser < Base
      # Parses error diagram source into an Error diagram model.
      #
      # @param source [String] the Mermaid error diagram source
      # @return [Diagram::Error] the parsed error diagram
      # @raise [ParseError] if syntax is invalid
      def parse(source)
        grammar = Grammars::Error.new

        begin
          parse_tree = grammar.parse(source)
        rescue Parslet::ParseFailed => e
          raise ParseError, "Syntax error at #{e.parse_failure_cause.pos}: " \
                           "#{e.parse_failure_cause}"
        end

        # Transform parse tree to diagram model
        transform = Transforms::Error.new
        diagram = transform.apply(parse_tree)

        diagram
      end
    end
  end
end