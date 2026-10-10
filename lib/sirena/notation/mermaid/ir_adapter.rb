# frozen_string_literal: true

module Sirena
  module Notation
    module Mermaid
      # Moves private Mermaid parse models onto the shared IR one type at a
      # time. Types without a migrated adapter keep their private model until
      # their own vertical lands.
      module IRAdapter
        module_function

        def call(type, diagram)
          row = Mermaid::TYPES[type]
          return diagram unless row&.fetch(:ir_adapter, false)

          require_relative "ir_adapters/#{type}"
          IRAdapters.const_get(class_name(type, row), false).call(diagram)
        end

        def class_name(type, row)
          row[:name] || type.to_s.split("_").map(&:capitalize).join
        end
        private_class_method :class_name
      end
    end
  end
end
