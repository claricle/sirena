# frozen_string_literal: true

require_relative 'base'
require_relative 'grammars/info'
require_relative 'transforms/info'
require_relative '../diagram/info'

module Sirena
  module Parser
    # Info diagram parser for Mermaid info diagram syntax.
    #
    # Uses Parslet grammar-based parsing to handle simple info diagrams.
    #
    # Parses info diagrams with support for:
    # - Basic info keyword
    # - Optional showInfo flag
    #
    # @example Parse a simple info diagram
    #   parser = InfoParser.new
    #   diagram = parser.parse("info")
    #
    # @example Parse info diagram with showInfo
    #   parser = InfoParser.new
    #   diagram = parser.parse("info showInfo")
    class InfoParser < Base
      # Parses info diagram source into an Info diagram model.
      #
      # @param source [String] the Mermaid info diagram source
      # @return [Diagram::Info] the parsed info diagram
      # @raise [ParseError] if syntax is invalid
      def parse(source)
        grammar = Grammars::Info.new

        begin
          parse_tree = grammar.parse(source)
        rescue Parslet::ParseFailed => e
          raise ParseError, "Syntax error at #{e.parse_failure_cause.pos}: " \
                           "#{e.parse_failure_cause}"
        end

        # Transform parse tree to diagram model
        transform = Transforms::Info.new
        diagram = transform.apply(parse_tree)

        diagram
      end
    end
  end
end