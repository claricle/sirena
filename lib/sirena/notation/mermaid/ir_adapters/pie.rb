# frozen_string_literal: true

require_relative "../../../ir"

module Sirena
  module Notation
    module Mermaid
      module IRAdapters
        # Maps Mermaid's private Pie model to notation-neutral ordered data.
        module Pie
          module_function

          def call(diagram)
            root_id = diagram.id || "pie"
            occupied = [root_id]
            dimension = dimension_for(occupied)
            values = slice_values(diagram, dimension.id, occupied)
            values << visibility_value(diagram, occupied)
            IR::Data.new(**data_attributes(diagram, root_id, dimension, values))
          end

          def data_attributes(diagram, root_id, dimension, values)
            {
              id: root_id, label: diagram.title, role: "proportional_series",
              accessibility_title: diagram.acc_title,
              accessibility_description: diagram.acc_description,
              dimensions: [dimension], values: values
            }
          end

          def dimension_for(occupied)
            IR::Dimension.new(
              id: reserve_id("category", occupied), role: "category",
            )
          end

          def slice_values(diagram, dimension_id, occupied)
            Array(diagram.slices).map.with_index do |slice, index|
              IR::DataValue.new(
                id: reserve_id("slice_#{index}", occupied),
                label: slice.label, role: "segment",
                dimension_id: dimension_id,
                value: IR::Scalar.new(number: slice.value)
              )
            end
          end

          def visibility_value(diagram, occupied)
            IR::DataValue.new(
              id: reserve_id("show_values", occupied), role: "show_values",
              value: IR::Scalar.new(boolean: diagram.show_data || false)
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
          private_class_method :data_attributes, :dimension_for, :slice_values,
                               :visibility_value, :reserve_id
        end
      end
    end
  end
end
