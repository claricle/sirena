# frozen_string_literal: true

require_relative "../../../ir"

module Sirena
  module Notation
    module Mermaid
      module IRAdapters
        # Maps Mermaid's private Packet model to a notation-neutral bit grid.
        module Packet
          module_function

          def call(diagram)
            root_id = diagram.id || "packet"
            occupied = [root_id]
            items = diagram.fields.map.with_index do |field, index|
              field_item(field, index, occupied)
            end
            IR::Prepositioned.new(
              id: root_id, label: diagram.title, role: "bit_grid", items: items,
            )
          end

          def field_item(field, index, occupied)
            IR::PrepositionedItem.new(
              id: reserve_id("field_#{index}", occupied),
              label: field.label, role: "field",
              placements: [IR::Placement.new(
                dimension: "bit", ordinal: index,
                value: IR::Scalar.new(number: field.bit_start),
                span: IR::Scalar.new(number: field.size)
              )]
            )
          end

          def reserve_id(preferred, occupied)
            candidate = preferred
            suffix = 2
            while occupied.include?(candidate)
              candidate = "#{preferred}_#{suffix}"
              suffix += 1
            end
            occupied << candidate
            candidate
          end
          private_class_method :field_item, :reserve_id
        end
      end
    end
  end
end
