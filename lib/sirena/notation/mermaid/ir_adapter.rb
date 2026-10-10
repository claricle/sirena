# frozen_string_literal: true

require_relative "ir_adapters/sankey"
require_relative "ir_adapters/mindmap"

module Sirena
  module Notation
    module Mermaid
      # Moves private Mermaid parse models onto the shared IR one type at a
      # time. Types without a migrated adapter keep their private model until
      # their own vertical lands.
      module IRAdapter
        ADAPTERS = {
          sankey: IRAdapters::Sankey,
          mindmap: IRAdapters::Mindmap,
        }.freeze
        private_constant :ADAPTERS

        module_function

        def call(type, diagram)
          adapter = ADAPTERS[type]
          adapter ? adapter.call(diagram) : diagram
        end
      end
    end
  end
end
