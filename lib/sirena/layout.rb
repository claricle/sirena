# frozen_string_literal: true

require_relative "layout/base"
require_relative "notation/mermaid"

module Sirena
  module Layout
    # A fresh layout for a diagram type, found by naming convention
    # (`:pie` -> `Layout::Pie`). Never cached: `Base#call` keeps the theme and
    # date on the instance.
    #
    # @param type [Symbol] a key of {Notation::Mermaid::TYPES}
    # @raise [Engine::DiagramTypeError] when the type is unknown
    # @raise [LayoutError] when the type has no layout class
    def self.for(type)
      Notation::Mermaid.layer_class(self, type, LayoutError).new
    end
  end
end
