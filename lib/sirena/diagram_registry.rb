# frozen_string_literal: true

require_relative "notation/mermaid"

module Sirena
  # Registry for Mermaid diagram type handlers.
  #
  # @deprecated A read-only facade over {Sirena::Notation::Mermaid::TYPES},
  #   kept for one release. A type is declared by its row there; there is
  #   nothing to register.
  class DiagramRegistry
    class << self
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
    end
  end
end
