# frozen_string_literal: true

require_relative "../../../ir"

module Sirena
  module Notation
    module Mermaid
      module IRAdapters
        # Maps Mermaid's private Mindmap tree to a notation-neutral graph.
        module Mindmap
          module_function

          def call(diagram)
            entries = entries_for(diagram)
            nodes = nodes_for(entries)
            occupied = nodes.map(&:id)
            IR::Graph.new(
              id: reserve_id("mindmap", occupied),
              label: diagram.title,
              role: "hierarchy",
              nodes: nodes,
              edges: edges_for(entries, occupied),
            )
          end

          def entries_for(diagram)
            return [] unless diagram.root

            flatten_subtree(diagram.root)
          end

          def nodes_for(entries)
            entries.map do |node, parent_id|
              IR::Node.new(
                id: node.id,
                label: node.content,
                role: node.shape || "default",
                parent_id: parent_id,
              )
            end
          end

          def edges_for(entries, occupied)
            entries.drop(1).map do |node, parent_id|
              IR::Edge.new(
                id: reserve_id("#{parent_id}_to_#{node.id}", occupied),
                source_id: parent_id,
                target_id: node.id,
                role: "parent_child",
              )
            end
          end

          def flatten_subtree(node, parent_id = nil)
            [[node, parent_id]] + node.children.flat_map do |child|
              flatten_subtree(child, node.id)
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
          private_class_method :entries_for, :nodes_for, :edges_for,
                               :flatten_subtree, :reserve_id
        end
      end
    end
  end
end
