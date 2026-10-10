# frozen_string_literal: true

require_relative "../../../ir"

module Sirena
  module Notation
    module Mermaid
      module IRAdapters
        # Maps an XY chart model to ordered axis and series constraints.
        module Xychart
          module_function

          def call(diagram)
            root_id = diagram.id || "xychart"
            occupied = [root_id]
            IR::Prepositioned.new(
              id: root_id, label: diagram.title, role: "coordinate_series",
              items: items_for(diagram, occupied)
            )
          end

          def items_for(diagram, occupied)
            horizontal = axis_item(
              diagram.x_axis, "horizontal", occupied, default_range: [0, 10]
            )
            vertical = axis_item(
              diagram.y_axis, "vertical", occupied, default_range: [0, 100]
            )
            items = [horizontal, *category_items(
              diagram.x_axis, horizontal.id, occupied
            ), vertical]
            items.concat(series_items(diagram.datasets, occupied))
          end

          def axis_item(axis, direction, occupied, default_range:)
            minimum, maximum = axis_range(axis, default_range)
            type = axis&.type || :numeric
            IR::PrepositionedItem.new(
              id: reserve_id("#{direction}_axis", occupied),
              label: axis&.label, role: "#{direction}_axis",
              placements: [
                placement("axis_direction", 0, direction),
                placement("axis_kind", 0, type),
                placement("minimum", 0, minimum),
                placement("maximum", 0, maximum),
              ]
            )
          end

          def axis_range(axis, default_range)
            return default_range unless axis

            axis.range
          end

          def category_items(axis, parent_id, occupied)
            return [] unless axis&.categorical?

            axis.values.map.with_index do |value, index|
              IR::PrepositionedItem.new(
                id: reserve_id("category_#{index}", occupied),
                label: value.to_s, role: "category", parent_id: parent_id,
                placements: [placement("category", index, value)]
              )
            end
          end

          def series_items(datasets, occupied)
            datasets.flat_map.with_index do |dataset, index|
              series = series_item(dataset, index, occupied)
              [series, *sample_items(dataset, series.id, occupied)]
            end
          end

          def series_item(dataset, index, occupied)
            IR::PrepositionedItem.new(
              id: reserve_id(dataset.id || "series_#{index}", occupied),
              label: dataset.label, role: "data_series",
              placements: series_placements(dataset, index)
            )
          end

          def series_placements(dataset, index)
            { series_order: index, chart_kind: dataset.chart_type,
              series_color: dataset.color }.filter_map do |dimension, value|
                placement(dimension.to_s, index, value) unless value.nil?
              end
          end

          def sample_items(dataset, parent_id, occupied)
            dataset.values.map.with_index do |value, index|
              IR::PrepositionedItem.new(
                id: reserve_id("#{parent_id}_sample_#{index}", occupied),
                role: "sample", parent_id: parent_id,
                placements: [placement("value", index, value)]
              )
            end
          end

          def placement(dimension, ordinal, value)
            IR::Placement.new(
              dimension: dimension, ordinal: ordinal, value: scalar(value),
            )
          end

          def scalar(value)
            return IR::Scalar.new(number: value) if value.is_a?(Numeric)

            IR::Scalar.new(text: value.to_s)
          end

          def reserve_id(preferred, occupied)
            candidate = preferred.to_s
            suffix = 2
            while occupied.include?(candidate)
              candidate = "#{preferred}_#{suffix}"
              suffix += 1
            end
            occupied << candidate
            candidate
          end
          private_class_method :items_for, :axis_item, :axis_range,
                               :category_items,
                               :series_items, :series_item, :sample_items,
                               :series_placements, :placement, :scalar,
                               :reserve_id
        end
      end
    end
  end
end
