# frozen_string_literal: true

require_relative "base"
require_relative "grammars/class_diagram"
require_relative "builders/class_diagram"
require_relative "class_notes"
require_relative "../diagram/class_diagram"

module Sirena
  module Parser
    # Class diagram parser for Mermaid class diagram syntax.
    #
    # Parses class diagrams with support for:
    # - Class declarations with stereotypes
    # - Attributes with visibility modifiers
    # - Methods with parameters and return types
    # - Relationships (inheritance, composition, aggregation, association)
    # - Generic types (e.g., List~String~)
    # - Namespaces
    # - Cardinality labels
    #
    # @example Parse a simple class diagram
    #   parser = ClassDiagram.new
    #   diagram = parser.parse("classDiagram\nAnimal <|-- Dog")
    class ClassDiagram < Base
      # Parses class diagram source into a ClassDiagram model.
      #
      # @param source [String] the Mermaid class diagram source
      # @return [Diagram::ClassDiagram] the parsed class diagram
      # @raise [ParseError] if syntax is invalid
      def parse(source)
        tree = parse_with_grammar(Grammars::ClassDiagram.new, source)
        diagram = Builders::ClassDiagram.new.apply(tree, source)
        diagram.notes = ClassNotes.collect(tree, diagram)
        diagram
      end
    end
  end
end
