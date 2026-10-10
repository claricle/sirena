# frozen_string_literal: true

require_relative "../../../ir"

module Sirena
  module Notation
    module Mermaid
      module IRAdapters
        # Maps Mermaid's private Sankey model to a notation-neutral graph.
        module Sankey
          module_function

          def call(diagram)
            nodes = nodes_for(diagram)
            occupied = nodes.map(&:id)
            IR::Graph.new(**graph_attributes(
              diagram, nodes, edges_for(diagram, occupied), occupied
            ))
          end

          def nodes_for(diagram)
            known = diagram.nodes.map(&:id)
            missing = diagram.all_node_ids - known
            private_nodes = diagram.nodes + missing.map do |id|
              diagram.node_by_id(id)
            end
            private_nodes.map do |node|
              IR::Node.new(
                id: node.id, label: node.display_label, role: "flow_node",
              )
            end
          end

          def edges_for(diagram, occupied)
            diagram.flows.map.with_index do |flow, index|
              IR::Edge.new(
                id: reserve_id("flow_#{index}", occupied),
                source_id: flow.source,
                target_id: flow.target,
                role: "weighted_flow",
                properties: IR::PropertySet.new(weight: flow.value),
              )
            end
          end

          def graph_attributes(diagram, nodes, edges, occupied)
            {
              id: reserve_id("sankey", occupied),
              label: diagram.title,
              role: "flow_network",
              accessibility_title: diagram.acc_title,
              accessibility_description: diagram.acc_description,
              nodes: nodes,
              edges: edges,
            }
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
          private_class_method :nodes_for, :edges_for, :graph_attributes,
                               :reserve_id
        end
      end
    end
  end
end
