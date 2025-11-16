# frozen_string_literal: true

require_relative 'base'
require_relative '../diagram/er_diagram'
require_relative 'grammars/er_diagram'
require_relative 'transforms/er_diagram'

module Sirena
  module Parser
    # ER diagram parser for Mermaid ER diagram syntax.
    #
    # Parses ER diagrams with support for:
    # - Entity declarations with attributes
    # - Attribute types and key markers (PK, FK, UK)
    # - Relationships with cardinality notation
    # - Identifying and non-identifying relationships
    #
    # @example Parse a simple ER diagram
    #   parser = ErDiagramParser.new
    #   diagram = parser.parse("erDiagram\nCUSTOMER ||--o{ ORDER : places")
    class ErDiagramParser < Base
      # Parses ER diagram source into an ErDiagram model.
      #
      # @param source [String] the Mermaid ER diagram source
      # @return [Diagram::ErDiagram] the parsed ER diagram
      # @raise [ParseError] if syntax is invalid
      def parse(source)
        grammar = Grammars::ErDiagram.new
        transform = Transforms::ErDiagram.new

        tree = grammar.parse(source)
        diagram = transform.apply(tree)

        diagram
      rescue Parslet::ParseFailed => e
        raise ParseError, e.parse_failure_cause.ascii_tree
      end
    end
  end
end
