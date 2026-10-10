# frozen_string_literal: true

require_relative "../../../ir"

module Sirena
  module Notation
    module Mermaid
      module IRAdapters
        # Maps Mermaid's private Treemap hierarchy to notation-neutral data.
        module Treemap
          STYLE_PROPERTIES = %i[fill stroke].freeze
          private_constant :STYLE_PROPERTIES

          module_function

          def call(diagram)
            entries = entries_for(diagram.root_nodes)
            series = series_for(entries)
            build_data(diagram, entries, series)
          end

          def build_data(diagram, entries, series)
            occupied = series.map(&:id)
            dimension = magnitude_dimension(occupied)
            IR::Data.new(
              id: reserve_id(diagram.id || "treemap", occupied),
              label: diagram.title,
              role: "hierarchical_partition", dimensions: [dimension],
              series: series,
              values: values_for(diagram, entries, dimension.id, occupied)
            )
          end

          def magnitude_dimension(occupied)
            IR::Dimension.new(
              id: reserve_id("magnitude", occupied), role: "magnitude",
            )
          end

          def values_for(diagram, entries, dimension_id, occupied)
            node_values(entries, dimension_id, occupied) +
              style_definitions(diagram.class_defs, occupied)
          end

          def entries_for(nodes, parent_id = nil, prefix = [])
            nodes.flat_map.with_index do |node, index|
              path = prefix + [index]
              id = "partition_#{path.join('_')}"
              [[node, id, parent_id]] + entries_for(node.children, id, path)
            end
          end

          def series_for(entries)
            entries.map do |node, id, parent_id|
              IR::Series.new(
                id: id, label: node.label, role: "partition",
                parent_id: parent_id
              )
            end
          end

          def node_values(entries, dimension_id, occupied)
            entries.flat_map do |node, id, _parent_id|
              values_for_node(node, id, dimension_id, occupied)
            end
          end

          def values_for_node(node, id, dimension_id, occupied)
            [
              magnitude_value(node, id, dimension_id, occupied),
              style_value(node, id, occupied),
            ].compact
          end

          def magnitude_value(node, id, dimension_id, occupied)
            return unless node.value

            data_value(
              "#{id}_magnitude", "magnitude", node.value, occupied,
              series_id: id, dimension_id: dimension_id
            )
          end

          def style_value(node, id, occupied)
            return unless node.css_class

            data_value(
              "#{id}_style", "style_reference", node.css_class, occupied,
              series_id: id
            )
          end

          def style_definitions(class_defs, occupied)
            class_defs.flat_map do |name, styles|
              STYLE_PROPERTIES.filter_map do |property|
                color = style_color(styles, property)
                next unless color

                data_value(
                  "style_#{name}_#{property}", "#{property}_color", color,
                  occupied, label: name
                )
              end
            end
          end

          def style_color(styles, property)
            match = styles.match(/#{property}:\s*([^;,]+)/)
            match[1].strip if match
          end

          def data_value(preferred_id, role, value, occupied, **attributes)
            scalar = if value.is_a?(Numeric)
                       IR::Scalar.new(number: value)
                     else
                       IR::Scalar.new(text: value)
                     end
            IR::DataValue.new(
              id: reserve_id(preferred_id, occupied), role: role,
              value: scalar, **attributes
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
          private_class_method :build_data, :magnitude_dimension, :values_for,
                               :entries_for, :series_for, :node_values,
                               :values_for_node, :magnitude_value, :style_value,
                               :style_definitions, :style_color, :data_value,
                               :reserve_id
        end
      end
    end
  end
end
