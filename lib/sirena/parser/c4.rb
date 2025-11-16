# frozen_string_literal: true

require_relative 'base'
require_relative 'grammars/c4'
require_relative 'transforms/c4'
require_relative '../diagram/c4'

module Sirena
  module Parser
    # C4 parser for Mermaid C4 diagram syntax.
    #
    # Uses Parslet grammar-based parsing to handle C4 diagram syntax including
    # elements, relationships, and boundaries.
    #
    # Parses C4 diagrams with support for:
    # - Multiple C4 levels (Context, Container, Component, Dynamic, Deployment)
    # - Person, System, Container, Component elements
    # - External variants (_Ext suffix)
    # - Database and Queue variants (SystemDb, ContainerQueue, etc.)
    # - Relationships (Rel, BiRel)
    # - Boundaries (Enterprise_Boundary, System_Boundary, Boundary)
    # - Nested boundaries
    # - Element attributes (sprite, link, tags)
    # - Layout configuration
    #
    # @example Parse a simple C4 Context diagram
    #   parser = C4Parser.new
    #   diagram = parser.parse("C4Context\ntitle My System\nPerson(user, \"User\")")
    class C4Parser < Base
      # Parses C4 diagram source into a C4 diagram model.
      #
      # @param source [String] the Mermaid C4 diagram source
      # @return [Diagram::C4] the parsed C4 diagram
      # @raise [ParseError] if syntax is invalid
      def parse(source)
        grammar = Grammars::C4.new

        begin
          parse_tree = grammar.parse(source)
        rescue Parslet::ParseFailed => e
          raise ParseError, "Syntax error at #{e.parse_failure_cause.pos}: " \
                           "#{e.parse_failure_cause}"
        end

        # Transform parse tree to diagram model
        transform = Transforms::C4.new
        diagram = transform.apply(parse_tree)

        diagram
      end
    end
  end
end