# frozen_string_literal: true

require_relative 'base'
require_relative 'grammars/class_diagram'
require_relative 'builders/class_diagram'
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
    #   parser = ClassDiagram.new
    #   diagram = parser.parse("classDiagram\nAnimal <|-- Dog")
    class ClassDiagram < Base
      # Parses class diagram source into a ClassDiagram model.
      #
      # @param source [String] the Mermaid class diagram source
      # @return [Diagram::ClassDiagram] the parsed class diagram
      # @raise [ParseError] if syntax is invalid
      def parse(source)
        tree = parse_grammar(source)
        Builders::ClassDiagram.new.apply(tree)
      end

      private

      # The name rules match Unicode letters, and Ruby refuses to match those
      # against a binary-tagged string that holds non-ASCII bytes. A
      # UTF-8-tagged string with invalid bytes raises ArgumentError from
      # Parslet's StringScanner.
      def parse_grammar(source)
        parse_with_grammar(Grammars::ClassDiagram.new, source)
      rescue EncodingError, ArgumentError => e
        raise ParseError, "Parse error: source encoding #{source.encoding} " \
                          "cannot be read as a class diagram (#{e.message})"
      end

      def format_parse_error(cause, source)
        lines = source.lines("\n")
        line_num, col_num = failure_position(cause, source)

        context = if line_num <= lines.length
                    lines[line_num - 1].chomp("\n")
                  else
                    '(end of input)'
                  end

        "Parse error at line #{line_num}, column #{col_num}:\n" \
          "#{context}\n" \
          "#{caret_for(lines[line_num - 1], col_num)}\n" \
          "#{failure_message(cause)}"
      end
    end
  end
end
