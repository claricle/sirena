# frozen_string_literal: true

require_relative 'base'
require_relative 'grammars/treemap'
require_relative 'transforms/treemap'
require_relative '../diagram/treemap'

module Sirena
  module Parser
    # Parser for treemap diagrams using Parslet
    class TreemapParser < Base
      def initialize
        super
        @grammar = Grammars::Treemap.new
      end

      # Parse treemap source into a TreemapDiagram
      #
      # @param source [String] The treemap diagram source
      # @return [Diagram::TreemapDiagram] The parsed diagram
      # @raise [ParseError] If parsing fails
      def parse(source)
        tree = @grammar.parse(source)
        Transforms::Treemap.apply_diagram(tree)
      rescue Parslet::ParseFailed => e
        raise ParseError, "Treemap parse error: #{e.message}"
      end
    end
  end
end
