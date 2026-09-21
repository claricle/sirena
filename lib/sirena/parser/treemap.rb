# frozen_string_literal: true

require_relative 'base'
require_relative 'grammars/treemap'
require_relative 'builders/treemap'
require_relative '../diagram/treemap'

module Sirena
  module Parser
    # Parser for treemap diagrams using Parslet
    class Treemap < Base
      def initialize
        super
        @grammar = Grammars::Treemap.new
      end

      # Parse treemap source into a Treemap
      #
      # @param source [String] The treemap diagram source
      # @return [Diagram::Treemap] The parsed diagram
      # @raise [ParseError] If parsing fails
      def parse(source)
        tree = @grammar.parse(source)
        Builders::Treemap.apply_diagram(tree)
      rescue Parslet::ParseFailed => e
        raise ParseError, "Treemap parse error: #{e.message}"
      end
    end
  end
end
