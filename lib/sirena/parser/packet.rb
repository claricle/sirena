# frozen_string_literal: true

require_relative "base"
require_relative "grammars/packet"
require_relative "builders/packet"
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
    #   parser = Packet.new
    #   source = <<~MERMAID
    #     packet-beta
    #       title Hello world
    #       0-10: "hello"
    #   MERMAID
    #   diagram = parser.parse(source)
    class Packet < Base
      grammar Grammars::Packet
      builder Builders::Packet

      private

      def create_diagram(result)
        diagram = Diagram::Packet.new
        return diagram unless result.is_a?(Hash)

        diagram.title = result[:title]
        append_fields(diagram, result[:fields])
        diagram
      end

      def append_fields(diagram, fields)
        Array(fields).each { |data| diagram.add_field(build_field(data)) }
      end

      def build_field(data)
        Diagram::PacketField.new(
          data[:bit_start], data[:bit_end], data[:label]
        )
      end
    end
  end
end
