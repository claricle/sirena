# frozen_string_literal: true

require_relative "base"
require_relative "../diagram/er_diagram"
require_relative "grammars/er_diagram"
require_relative "builders/er_diagram"

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
    #   parser = ErDiagram.new
    #   diagram = parser.parse("erDiagram\nCUSTOMER ||--o{ ORDER : places")
    class ErDiagram < Base
      grammar Grammars::ErDiagram
      builder Builders::ErDiagram
    end
  end
end
