# frozen_string_literal: true

require_relative "parser/base"
require_relative "notation/mermaid"

module Sirena
  module Parser
    # A fresh parser for a diagram type, found by naming convention
    # (`:pie` -> `Parser::Pie`). Never cached.
    #
    # @param type [Symbol] a key of {Notation::Mermaid::TYPES}
    # @raise [Engine::DiagramTypeError] when the type is unknown
    # @raise [ParseError] when the type has no parser class
    def self.for(type)
      Notation::Mermaid.layer_class(self, type, ParseError).new
    end
  end
end
