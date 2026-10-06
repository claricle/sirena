# frozen_string_literal: true

require_relative "notation/mermaid"

module Sirena
  # Registry for Mermaid diagram type handlers.
  #
  # @deprecated A thin facade over {Sirena::Notation::Mermaid}'s type table,
  #   kept for one release. Register types with
  #   {Sirena::Notation::Mermaid.register_type}.
  #
  # @example Registering a diagram type
  #   DiagramRegistry.register(
  #     :flowchart,
  #     parser: Parser::Flowchart,
  #     transform: Layout::Flowchart,
  #     renderer: Renderer::Flowchart,
  #     model: Diagram::Flowchart
  #   )
  class DiagramRegistry
    class << self
      # Registers handlers for a diagram type.
      #
      # @param type [Symbol] diagram type identifier
      # @param parser [Class] parser class
      # @param transform [Class] transform class
      # @param renderer [Class] renderer class
      # @param model [Class] diagram model class
      def register(type, parser:, transform:, renderer:, model:)
        Notation::Mermaid.register_type(
          type, parser: parser, transform: transform,
                renderer: renderer, model: model
        )
      end

      # @return [Hash, nil] handlers for a type, nil when not registered
      def get(type)
        Notation::Mermaid.type_handlers(type)
      end

      # @return [Array<Symbol>] registered types in registration order
      def types
        Notation::Mermaid.types
      end

      def registered?(type)
        Notation::Mermaid.type_registered?(type)
      end

      def clear
        Notation::Mermaid.clear_types
      end
    end
  end
end
