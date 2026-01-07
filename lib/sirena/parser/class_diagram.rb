# frozen_string_literal: true

require_relative 'base'
require_relative 'grammars/class_diagram'
require_relative 'transforms/class_diagram'
require_relative '../diagram/class_diagram'

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
    #   parser = ClassDiagramParser.new
    #   diagram = parser.parse("classDiagram\nAnimal <|-- Dog")
    class ClassDiagramParser < Base
      # Parses class diagram source into a ClassDiagram model.
      #
      # @param source [String] the Mermaid class diagram source
      # @return [Diagram::ClassDiagram] the parsed class diagram
      # @raise [ParseError] if syntax is invalid
      def parse(source)
        grammar = Grammars::ClassDiagram.new
        transform = Transforms::ClassDiagram.new

        begin
          parse_tree = grammar.parse(source)
          diagram = transform.apply(parse_tree)
          diagram
        rescue Parslet::ParseFailed => e
          raise ParseError, format_parse_error(e, source)
        end
      end

      private

      def format_parse_error(error, source)
        lines = source.lines
        line_num = error.parse_failure_cause.source.line_and_column[0]
        col_num = error.parse_failure_cause.source.line_and_column[1]

        context = if line_num <= lines.length
                    lines[line_num - 1].chomp
                  else
                    '(end of input)'
                  end

        "Parse error at line #{line_num}, column #{col_num}:\n" \
          "#{context}\n" \
          "#{' ' * (col_num - 1)}^\n" \
          "Expected: #{error.parse_failure_cause.message}"
      end
    end
  end
end
