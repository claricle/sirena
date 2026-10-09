# frozen_string_literal: true

require_relative "base"
require_relative "grammars/treemap"
require_relative "builders/treemap"
require_relative "../diagram/treemap"

module Sirena
  module Parser
    # Parser for treemap diagrams using Parslet
    class Treemap < Base
      # Parse treemap source into a Treemap
      #
      # @param source [String] The treemap diagram source
      # @return [Diagram::Treemap] The parsed diagram
      # @raise [ParseError] If parsing fails
      def parse(source)
        tree = parse_with_grammar(Grammars::Treemap.new, source)
        Builders::Treemap.apply_diagram(tree)
      end
    end
  end
end
