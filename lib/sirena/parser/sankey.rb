# frozen_string_literal: true

require_relative "base"
require_relative "grammars/sankey"
require_relative "builders/sankey"
require_relative "../diagram/sankey"

module Sirena
  module Parser
    # Sankey parser for Mermaid sankey diagram syntax.
    #
    # Uses Parslet grammar-based parsing to handle Sankey diagram syntax
    # with flows between nodes and optional node labels.
    #
    # Parses Sankey diagrams with support for:
    # - Flow definitions (CSV format: source,target,value)
    # - Optional node declarations with labels
    # - Automatic node discovery from flows
    # - Numeric flow values (integer or float)
    # - Comments
    #
    # @example Parse a simple Sankey diagram
    #   parser = Sankey.new
    #   diagram = parser.parse(<<~SANKEY)
    #     sankey-beta
    #     A,B,10
    #     B,C,20
    #     A,D,5
    #   SANKEY
    #
    # @example Parse Sankey with node labels
    #   parser = Sankey.new
    #   diagram = parser.parse(<<~SANKEY)
    #     sankey-beta
    #     Source [Energy Source]
    #     Process [Processing Plant]
    #     Source,Process,100
    #     Process,Output,70
    #   SANKEY
    class Sankey < Base
      # Parses Sankey diagram source into a Sankey model.
      #
      # @param source [String] the Mermaid Sankey diagram source
      # @return [Diagram::Sankey] the parsed Sankey diagram
      # @raise [ParseError] if syntax is invalid
      def parse(source)
        grammar = Grammars::Sankey.new

        begin
          parse_tree = grammar.parse(source)
        rescue Parslet::ParseFailed => e
          raise ParseError, "Syntax error at #{e.parse_failure_cause.pos}: " \
                           "#{e.parse_failure_cause}"
        end

        # Transform parse tree to diagram model
        transform = Builders::Sankey.new
        diagram = transform.apply(parse_tree)

        diagram
      end
    end
  end
end