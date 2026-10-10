# frozen_string_literal: true

require_relative "renderer/base"
require_relative "notation/mermaid"
require_relative "theme/completion"

module Sirena
  module Renderer
    # A fresh renderer for a diagram type, found by naming convention
    # (`:pie` -> `Renderer::Pie`). Never cached.
    #
    # @param type [Symbol] a key of {Notation::Mermaid::TYPES}
    # @param theme [Theme, nil] the theme the renderer draws with; colours it
    #   leaves unset come from the default theme
    # @raise [Engine::DiagramTypeError] when the type is unknown
    # @raise [RenderError] when the type has no renderer class
    def self.for(type, theme: nil)
      renderer = Notation::Mermaid.layer_class(self, type, RenderError)
      renderer.new(theme: Theme::Completion.call(theme))
    end
  end
end
