# frozen_string_literal: true

require_relative 'base'
require_relative 'grammars/sequence'
require_relative 'transforms/sequence'
require_relative '../diagram/sequence'

module Sirena
  module Parser
    # Sequence parser for Mermaid sequence diagram syntax.
    #
    # Uses Parslet grammar-based parsing to correctly handle complex arrow
    # patterns with activation modifiers (e.g., `->>+`, `-->>-`) that cannot
    # be parsed accurately with regex-based lexers.
    #
    # Parses sequence diagrams with support for:
    # - Participant declarations (participant, actor)
    # - Multiple message types with activation modifiers
    # - Activations and deactivations
    # - Notes (left of, right of, over)
    # - Control structures (loop, alt, opt, par, critical, break)
    # - Box grouping
    #
    # @example Parse a simple sequence diagram
    #   parser = SequenceParser.new
    #   diagram = parser.parse("sequenceDiagram\nAlice->>Bob: Hello")
    class SequenceParser < Base
      # Parses sequence diagram source into a Sequence diagram model.
      #
      # @param source [String] the Mermaid sequence diagram source
      # @return [Diagram::Sequence] the parsed sequence diagram
      # @raise [ParseError] if syntax is invalid
      def parse(source)
        grammar = Grammars::Sequence.new

        begin
          parse_tree = grammar.parse(source)
        rescue Parslet::ParseFailed => e
          raise ParseError, "Syntax error at #{e.parse_failure_cause.pos}: " \
                           "#{e.parse_failure_cause}"
        end

        # Transform parse tree to diagram model
        transform = Transforms::Sequence.new
        diagram = transform.apply(parse_tree)

        diagram
      end
    end
  end
end
