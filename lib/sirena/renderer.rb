# frozen_string_literal: true

require_relative "renderer/base"
require_relative "notation/mermaid"

module Sirena
  module Renderer
    # A fresh renderer for a diagram type, found by naming convention
    # (`:pie` -> `Renderer::Pie`). Never cached.
    #
    # @param type [Symbol] a key of {Notation::Mermaid::TYPES}
    # @param theme [Theme, nil] the theme the renderer draws with
    # @raise [Engine::DiagramTypeError] when the type is unknown
    # @raise [RenderError] when the type has no renderer class
    def self.for(type, theme: nil)
      Notation::Mermaid.layer_class(self, type, RenderError).new(theme: theme)
    end
  end
end
