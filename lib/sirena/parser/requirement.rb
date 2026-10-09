# frozen_string_literal: true

require_relative "base"
require_relative "grammars/requirement"
require_relative "builders/requirement"
require_relative "../diagram/requirement"

module Sirena
  module Parser
    # Requirement diagram parser for Mermaid requirement diagram syntax.
    #
    # Parses requirement diagrams with support for:
    # - Requirements with properties (id, text, risk, verifymethod)
    # - Multiple requirement types (requirement, functionalRequirement, etc.)
    # - Elements with properties (type, docref)
    # - Relationships (contains, copies, derives, satisfies, verifies, refines, traces)
    # - Styling directives
    # - Class definitions and assignments
    #
    # @example Parse a simple requirement diagram
    #   parser = Requirement.new
    #   diagram = parser.parse("requirementDiagram\n  requirement test_req { id: 1 }")
    class Requirement < Base
      # Parses requirement diagram source into a Requirement model.
      #
      # @param source [String] the Mermaid requirement diagram source
      # @return [Diagram::Requirement] the parsed requirement diagram
      # @raise [ParseError] if syntax is invalid
      def parse(source)
        tree = parse_tree(source)
        Builders::Requirement.apply(tree)
      end

      private

      def parse_tree(source)
        parse_with_grammar(Grammars::Requirement.new, source)
      rescue EncodingError, ArgumentError => e
        raise ParseError, "Parse error: source encoding #{source.encoding} " \
                          "cannot be read as a requirement diagram (#{e.message})"
      end
    end
  end
end
