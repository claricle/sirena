# frozen_string_literal: true

require_relative "../../../ir"

module Sirena
  module Notation
    module Mermaid
      module IRAdapters
        # Maps Mermaid's private Flowchart model to a notation-neutral graph.
        module Flowchart
          module_function

          def call(diagram)
            return diagram unless diagram.valid?

            adapt(diagram)
          end

          def adapt(diagram)
            occupied = []
            boxes = drawable_boxes(diagram)
            box_ids = identity_map(boxes, occupied)
            node_ids = identity_map(diagram.nodes, occupied)
            nodes = entity_nodes(diagram, boxes, box_ids, node_ids, occupied)
            edges = edge_nodes(diagram.edges || [], node_ids, box_ids, occupied)
            settings = settings_nodes(diagram, occupied)
            IR::Graph.new(**graph_attributes(
              diagram, nodes + settings, edges, occupied
            ))
          end

          def entity_nodes(diagram, boxes, box_ids, node_ids, occupied)
            holders = node_holders(boxes, box_ids)
            flow_nodes = diagram.nodes.flat_map do |node|
              flow_node(node, node_ids.fetch(node), holders[node.id], occupied)
            end
            groups = boxes.flat_map do |box|
              group_node(box, box_ids, occupied)
            end
            flow_nodes + groups
          end

          def flow_node(node, id, parent_id, occupied)
            entity = IR::Node.new(
              id: id, label: node.label, role: "flow_node",
              parent_id: parent_id
            )
            semantics = [["source_identifier", node.id],
                         ["shape", node.shape],
                         ["style_reference", node.classes]]
            [entity, *semantic_nodes(id, semantics, occupied)]
          end

          def group_node(box, box_ids, occupied)
            id = box_ids.fetch(box)
            entity = IR::Node.new(
              id: id, label: box.title, role: "group",
              parent_id: source_index(box_ids)[box.parent_id]
            )
            semantics = [["source_identifier", box.id],
                         ["layout_direction", box.direction]]
            [entity, *semantic_nodes(id, semantics, occupied)]
          end

          def edge_nodes(edges, node_ids, box_ids, occupied)
            endpoints = first_source_index(box_ids).merge(
              first_source_index(node_ids),
            )
            edges.map { |edge| edge_node(edge, endpoints, occupied) }
          end

          def edge_node(edge, endpoints, occupied)
            preferred = "#{edge.source_id}_to_#{edge.target_id}"
            IR::Edge.new(
              id: reserve_id(preferred, occupied),
              source_id: endpoints.fetch(edge.source_id),
              target_id: endpoints.fetch(edge.target_id),
              label: edge.label, role: edge.arrow_type,
              properties: marker_properties(edge.arrow_type)
            )
          end

          def marker_properties(arrow_type)
            marker = arrow_type.to_s.sub(/\A(?:thick|dotted)_/, "")
            both = marker.delete_suffix!("_both")
            marker = nil if %w[line invisible].include?(marker)
            IR::PropertySet.new(
              source_marker: both ? marker : nil, target_marker: marker,
            )
          end

          def settings_nodes(diagram, occupied)
            id = reserve_id("diagram_settings", occupied)
            values = [["diagram_identifier", diagram.id || "flowchart"],
                      ["layout_direction", diagram.direction],
                      ["theme_reference", diagram.theme]]
            [IR::Node.new(id: id, role: "diagram_settings"),
             *semantic_nodes(id, values, occupied)]
          end

          def semantic_nodes(parent_id, values, occupied)
            values.filter_map do |role, value|
              next if value.nil?

              IR::Node.new(
                id: reserve_id("#{parent_id}_#{role}", occupied),
                label: value.to_s, role: role, parent_id: parent_id
              )
            end
          end

          def graph_attributes(diagram, nodes, edges, occupied)
            {
              id: reserve_id(diagram.id || "flowchart", occupied),
              label: diagram.title, role: "flow_diagram",
              accessibility_title: accessibility(diagram, :acc_title),
              accessibility_description: accessibility(
                diagram, :acc_description, :acc_descr
              ),
              nodes: nodes, edges: edges
            }
          end

          def accessibility(diagram, *names)
            names.each do |name|
              next unless diagram.respond_to?(name)

              value = diagram.public_send(name)
              return value unless value.nil?
            end
            nil
          end

          def drawable_boxes(diagram)
            (diagram.subgraphs || []).select(&:drawable?)
          end

          def node_holders(boxes, box_ids)
            boxes.each_with_object({}) do |box, holders|
              box_id = box_ids.fetch(box)
              box.node_ids.each { |source_id| holders[source_id] = box_id }
            end
          end

          def identity_map(items, occupied)
            items.each_with_object({}.compare_by_identity) do |item, result|
              result[item] = reserve_id(item.id, occupied)
            end
          end

          def source_index(identities)
            identities.each_with_object({}) do |(item, id), index|
              index[item.id] = id
            end
          end

          def first_source_index(identities)
            identities.each_with_object({}) do |(item, id), index|
              index[item.id] ||= id
            end
          end

          def reserve_id(preferred, occupied)
            preferred = preferred.to_s
            preferred = "item" if preferred.empty?
            candidate = preferred
            suffix = 2
            while occupied.include?(candidate)
              candidate = "#{preferred}_#{suffix}"
              suffix += 1
            end
            occupied << candidate
            candidate
          end
          private_class_method :adapt, :entity_nodes, :flow_node, :group_node,
                               :edge_nodes, :edge_node, :marker_properties,
                               :settings_nodes, :semantic_nodes,
                               :graph_attributes, :accessibility,
                               :drawable_boxes, :node_holders, :identity_map,
                               :source_index, :first_source_index, :reserve_id
        end
      end
    end
  end
end
