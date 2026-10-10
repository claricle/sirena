# frozen_string_literal: true

require_relative "../../../ir"

module Sirena
  module Notation
    module Mermaid
      module IRAdapters
        # Maps Mermaid's private Info model to notation-neutral data.
        module Info
          module_function

          def call(diagram)
            root_id = diagram.id || "info"
            IR::Data.new(
              id: root_id, label: diagram.title, role: "information_panel",
              values: [IR::DataValue.new(
                id: value_id(root_id), role: "show_information",
                value: IR::Scalar.new(boolean: diagram.show_info || false)
              )]
            )
          end

          def value_id(root_id)
            return "show_information_2" if root_id == "show_information"

            "show_information"
          end
          private_class_method :value_id
        end
      end
    end
  end
end
