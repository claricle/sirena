# frozen_string_literal: true

require_relative "base"
require_relative "grammars/packet"
require_relative "transforms/packet"
require_relative "../diagram/packet"

module Sirena
  module Parser
    # Packet diagram parser for Mermaid packet-beta diagram syntax.
    #
    # Uses Parslet grammar-based parsing to handle packet diagram syntax
    # with bit ranges and field labels.
    #
    # Parses packet diagrams with support for:
    # - Title metadata
    # - Field definitions with bit ranges
    # - Field labels
    #
    # @example Parse a simple packet diagram
    #   parser = PacketParser.new
    #   source = <<~MERMAID
    #     packet-beta
    #       title Hello world
    #       0-10: "hello"
    #   MERMAID
    #   diagram = parser.parse(source)
    class PacketParser < Base
      # Parses packet diagram source into a PacketDiagram model.
      #
      # @param source [String] the Mermaid packet diagram source
      # @return [Diagram::PacketDiagram] the parsed packet diagram
      # @raise [ParseError] if syntax is invalid
      def parse(source)
        grammar = Grammars::Packet.new

        begin
          parse_tree = grammar.parse(source)
        rescue Parslet::ParseFailed => e
          raise ParseError, "Syntax error at #{e.parse_failure_cause.pos}: " \
                           "#{e.parse_failure_cause}"
        end

        # Transform parse tree to intermediate representation
        transform = Transforms::Packet.new
        result = transform.apply(parse_tree)

        # Create the diagram model
        create_diagram(result)
      end

      private

      def create_diagram(result)
        diagram = Diagram::PacketDiagram.new

        # Handle case where result is not a hash (empty diagram)
        return diagram unless result.is_a?(Hash)

        diagram.title = result[:title]

        # Create fields
        Array(result[:fields]).each do |field_data|
          field = Diagram::PacketField.new(
            field_data[:bit_start],
            field_data[:bit_end],
            field_data[:label]
          )
          diagram.add_field(field)
        end

        diagram
      end
    end
  end
end