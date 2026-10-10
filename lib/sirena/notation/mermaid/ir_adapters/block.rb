# frozen_string_literal: true

require_relative "../../../ir"

module Sirena
  module Notation
    module Mermaid
      module IRAdapters
        # Maps Mermaid's private Block model to a notation-neutral grid.
        module Block
          module_function

          def call(diagram)
            entries = flatten(diagram.blocks)
            occupied = []
            ids = ids_for(entries, occupied)
            build_document(diagram, entries, ids, occupied)
          end

          def ids_for(entries, occupied)
            entries.each_with_object({}.compare_by_identity) do |entry, ids|
              block, _parent, index = entry
              preferred = block.id || "block_#{index}"
              ids[block] = reserve_id(preferred, occupied)
            end
          end

          def build_document(diagram, entries, ids, occupied)
            root_id = reserve_id(diagram.id || "block", occupied)
            settings = settings_item(diagram.columns, occupied)
            IR::Prepositioned.new(
              id: root_id, label: diagram.title, role: "column_grid",
              items: [settings] + block_items(entries, ids),
              connections: connections(
                diagram.connections, entries, ids, occupied
              )
            )
          end

          def block_items(entries, ids)
            entries.map do |block, parent, index|
              block_item(block, parent, index, ids)
            end
          end

          def flatten(blocks, parent = nil, entries = [])
            blocks.each do |block|
              entries << [block, parent, entries.length]
              flatten(block.children, block, entries)
            end
            entries
          end

          def settings_item(columns, occupied)
            IR::PrepositionedItem.new(
              id: reserve_id("layout_settings", occupied),
              role: "layout_settings",
              placements: [placement("column_count", 0, number: columns)],
            )
          end

          def block_item(block, parent, index, ids)
            IR::PrepositionedItem.new(
              id: ids.fetch(block), label: block.label,
              role: block.block_type || "block",
              parent_id: parent && ids.fetch(parent),
              placements: block_placements(block, index)
            )
          end

          def block_placements(block, index)
            placements = [
              placement("source_order", 0, number: index),
              placement("column_span", 1, number: block.width || 1),
              placement("compound", 2, boolean: block.compound?),
            ]
            if block.shape
              placements << placement("shape", 3, text: block.shape)
            end
            if block.direction
              placements << placement("direction", 4, text: block.direction)
            end
            placements
          end

          def connections(source, entries, ids, occupied)
            ids_by_source = source_ids(entries, ids)
            source.filter_map.with_index do |connection, index|
              source_id = ids_by_source[connection.from]
              target_id = ids_by_source[connection.to]
              next unless source_id && target_id

              edge(connection, index, source_id, target_id, occupied)
            end
          end

          def source_ids(entries, ids)
            entries.to_h do |block, _parent, _index|
              [block.id, ids.fetch(block)]
            end
          end

          def edge(connection, index, source_id, target_id, occupied)
            IR::Edge.new(
              id: reserve_id("edge_#{index}", occupied),
              label: connection.label, role: connection.connection_type,
              source_id: source_id, target_id: target_id
            )
          end

          def placement(dimension, ordinal, **scalar)
            IR::Placement.new(
              dimension: dimension, ordinal: ordinal,
              value: IR::Scalar.new(scalar)
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
          private_class_method :ids_for, :build_document, :block_items,
                               :flatten, :settings_item, :block_item,
                               :block_placements, :connections, :source_ids,
                               :edge, :placement, :reserve_id
        end
      end
    end
  end
end
