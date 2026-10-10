# frozen_string_literal: true

require_relative "../../../ir"

module Sirena
  module Notation
    module Mermaid
      module IRAdapters
        # Maps Mermaid's private Error model to notation-neutral data.
        module Error
          module_function

          def call(diagram)
            root_id = diagram.id || "error"
            IR::Data.new(
              id: root_id, label: diagram.title, role: "error_panel",
              items: [IR::Item.new(
                id: message_id(root_id), label: diagram.message,
                role: "message"
              )]
            )
          end

          def message_id(root_id)
            root_id == "message" ? "message_2" : "message"
          end
          private_class_method :message_id
        end
      end
    end
  end
end
