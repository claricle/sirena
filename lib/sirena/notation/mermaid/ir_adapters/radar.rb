# frozen_string_literal: true

require_relative "../../../ir"

module Sirena
  module Notation
    module Mermaid
      module IRAdapters
        # Maps Mermaid's private Radar model to notation-neutral ordered data.
        module Radar
          OPTION_ROLES = {
            min: "lower_bound",
            max: "upper_bound",
            ticks: "tick_count",
            show_legend: "legend_visibility",
            graticule: "grid_shape",
          }.freeze
          private_constant :OPTION_ROLES

          module_function

          def call(diagram)
            occupied = []
            dimensions, dimension_ids = dimensions_for(diagram, occupied)
            series, series_ids = series_for(diagram, occupied)
            build_data(
              diagram, dimensions, series, dimension_ids + series_ids,
              occupied
            )
          end

          def build_data(diagram, dimensions, series, identities, occupied)
            root_id = reserve_id(diagram.id || "radar", occupied)
            IR::Data.new(
              id: root_id, label: diagram.title, role: "radial_comparison",
              accessibility_title: diagram.acc_title,
              accessibility_description: diagram.acc_descr,
              dimensions: dimensions, series: series,
              values: values_for(
                diagram, dimensions, series, identities, occupied
              )
            )
          end

          def values_for(diagram, dimensions, series, identities, occupied)
            identifier_values(identities, occupied) +
              measurement_values(diagram, dimensions, series, occupied) +
              option_values(diagram.options, occupied)
          end

          def dimensions_for(diagram, occupied)
            identities = []
            dimensions = diagram.axes.map do |axis|
              id = reserve_id(axis.id, occupied)
              identities << [id, axis.id] if id != axis.id
              IR::Dimension.new(id: id, label: axis.label, role: "axis")
            end
            [dimensions, identities]
          end

          def series_for(diagram, occupied)
            identities = []
            series = diagram.curves.map do |curve|
              id = reserve_id(curve.id, occupied)
              identities << [id, curve.id] if id != curve.id
              IR::Series.new(
                id: id, label: curve.label, role: "dataset",
              )
            end
            [series, identities]
          end

          def identifier_values(identities, occupied)
            identities.map do |item_id, source_id|
              IR::DataValue.new(
                id: reserve_id("#{item_id}_identifier", occupied),
                parent_id: item_id, role: "identifier",
                value: IR::Scalar.new(text: source_id)
              )
            end
          end

          def measurement_values(diagram, dimensions, series, occupied)
            diagram.curves.zip(series).flat_map do |curve, dataset|
              diagram.axes.zip(dimensions).map do |axis, dimension|
                measurement_value(
                  curve, dataset, axis, dimension, occupied
                )
              end
            end
          end

          def measurement_value(curve, dataset, axis, dimension, occupied)
            IR::DataValue.new(
              id: reserve_id("#{dataset.id}_#{dimension.id}", occupied),
              role: "measurement", dimension_id: dimension.id,
              series_id: dataset.id,
              value: IR::Scalar.new(number: curve.value_for(axis.id))
            )
          end

          def option_values(options, occupied)
            OPTION_ROLES.filter_map do |name, role|
              next unless options.key?(name)

              IR::DataValue.new(
                id: reserve_id(role, occupied), role: role,
                value: scalar(options.fetch(name))
              )
            end
          end

          def scalar(value)
            case value
            when Numeric
              IR::Scalar.new(number: value)
            when true, false
              IR::Scalar.new(boolean: value)
            else
              IR::Scalar.new(text: value.to_s)
            end
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
          private_class_method :build_data, :values_for, :dimensions_for,
                               :series_for, :identifier_values,
                               :measurement_values, :measurement_value,
                               :option_values, :scalar, :reserve_id
        end
      end
    end
  end
end
