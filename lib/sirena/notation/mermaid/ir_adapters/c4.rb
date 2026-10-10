# frozen_string_literal: true

require_relative "../../../ir"

module Sirena
  module Notation
    module Mermaid
      module IRAdapters
        # Maps Mermaid's private C4 model to a notation-neutral graph.
        module C4
          ELEMENT_ROLES = {
            "Person" => "person",
            "System" => "system",
            "SystemDb" => "system_database",
            "SystemQueue" => "system_queue",
            "Container" => "container",
            "ContainerDb" => "container_database",
            "ContainerQueue" => "container_queue",
            "Component" => "component",
          }.freeze
          BOUNDARY_ROLES = {
            "Enterprise_Boundary" => "enterprise_boundary",
            "System_Boundary" => "system_boundary",
            "Boundary" => "boundary",
          }.freeze
          private_constant :ELEMENT_ROLES, :BOUNDARY_ROLES

          module_function

          def call(diagram)
            occupied = []
            boundary_ids = identity_map(diagram.boundaries, occupied,
                                        "boundary")
            element_ids = identity_map(diagram.elements, occupied, "element")
            nodes, edges = graph_contents(
              diagram, boundary_ids, element_ids, occupied
            )
            IR::Graph.new(**graph_attributes(diagram, nodes, edges, occupied))
          end

          def graph_contents(diagram, boundary_ids, element_ids, occupied)
            nodes = entity_nodes(diagram, boundary_ids, element_ids, occupied)
            relationship_nodes, edges = relationships(
              diagram, element_ids, occupied
            )
            nodes.concat(relationship_nodes)
            nodes.concat(settings_nodes(diagram, occupied))
            [nodes, edges]
          end

          def graph_attributes(diagram, nodes, edges, occupied)
            {
              id: reserve_id(diagram.id || "c4", occupied),
              label: diagram.title, role: "architecture_graph",
              nodes: nodes, edges: edges
            }
          end

          def identity_map(items, occupied, fallback)
            items.each_with_index.to_h do |item, index|
              preferred = item.id.to_s.empty? ? "#{fallback}_#{index}" : item.id
              [item, reserve_id(preferred, occupied)]
            end
          end

          def entity_nodes(diagram, boundary_ids, element_ids, occupied)
            boundary_index = source_index(diagram.boundaries, boundary_ids)
            boundaries = boundary_nodes(
              diagram.boundaries, boundary_ids, boundary_index, occupied
            )
            elements = element_nodes(
              diagram.elements, element_ids, boundary_index, occupied
            )
            boundaries + elements
          end

          def boundary_nodes(boundaries, identities, parent_index, occupied)
            boundaries.flat_map do |boundary|
              boundary_node(boundary, identities, parent_index, occupied)
            end
          end

          def element_nodes(elements, identities, parent_index, occupied)
            elements.flat_map do |element|
              element_node(element, identities, parent_index, occupied)
            end
          end

          def source_index(items, identities)
            items.each_with_object({}) do |item, index|
              index[item.id] ||= identities.fetch(item)
            end
          end

          def boundary_node(boundary, identities, parent_index, occupied)
            id = identities.fetch(boundary)
            node = IR::Node.new(
              id: id, label: boundary.label, role: boundary_role(boundary),
              parent_id: parent_index[boundary.parent_id]
            )
            details = semantic_nodes(
              id, boundary_values(boundary), occupied
            )
            [node, *details]
          end

          def boundary_values(boundary)
            [["original_identifier", boundary.id],
             ["boundary_type", boundary.boundary_type],
             ["parent_identifier", boundary.parent_id],
             ["type_label", boundary.type_param], ["link", boundary.link],
             ["tags", boundary.tags]]
          end

          def element_node(element, identities, boundary_index, occupied)
            id = identities.fetch(element)
            node = IR::Node.new(
              id: id, label: element.label, role: element_role(element),
              parent_id: boundary_index[element.boundary_id]
            )
            details = semantic_nodes(id, element_values(element), occupied)
            [node, *details]
          end

          def element_values(element)
            [["original_identifier", element.id],
             ["element_type", element.element_type],
             ["boundary_identifier", element.boundary_id],
             ["description", element.description],
             ["technology", element.technology], ["sprite", element.sprite],
             ["link", element.link], ["tags", element.tags],
             ["external", element.external]]
          end

          def relationships(diagram, identities, occupied)
            element_index = source_index(diagram.elements, identities)
            records = diagram.relationships.map.with_index do |relation, index|
              relationship_record(
                relation, index, element_index, occupied
              )
            end
            [records.flat_map(&:first), records.map(&:last)]
          end

          def relationship_record(relation, index, element_index, occupied)
            detail_id = reserve_id("relationship_details_#{index}", occupied)
            details = relationship_details(relation, detail_id, occupied)
            edge = relationship_edge(
              relation, index, detail_id, element_index, occupied
            )
            [details, edge]
          end

          def relationship_details(relation, detail_id, occupied)
            node = IR::Node.new(
              id: detail_id, role: "relationship_details",
            )
            values = relationship_values(relation)
            [node, *semantic_nodes(detail_id, values, occupied)]
          end

          def relationship_values(relationship)
            [["relationship_type", relationship.rel_type],
             ["technology", relationship.technology]]
          end

          def relationship_edge(relationship, index, detail_id, elements,
                                occupied)
            attributes = relationship_attributes(
              relationship, index, detail_id, elements, occupied
            )
            IR::Edge.new(**attributes)
          end

          def relationship_attributes(relationship, index, detail_id,
                                      elements, occupied)
            bidirectional = relationship.bidirectional?
            {
              id: reserve_id("relationship_#{index}", occupied),
              label: relationship.label,
              role: relationship_role(bidirectional),
              parent_id: detail_id, source_id: elements[relationship.from_id],
              target_id: elements[relationship.to_id],
              properties: relationship_properties(bidirectional)
            }
          end

          def relationship_properties(bidirectional)
            IR::PropertySet.new(
              source_marker: bidirectional ? "arrow" : nil,
              target_marker: "arrow",
            )
          end

          def relationship_role(bidirectional)
            return "bidirectional_relationship" if bidirectional

            "relationship"
          end

          def settings_nodes(diagram, occupied)
            id = reserve_id("diagram_settings", occupied)
            values = [
              ["diagram_identifier", diagram.id], ["level", diagram.level],
              ["layout_intent", diagram.layout_config]
            ]
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

          def element_role(element)
            ELEMENT_ROLES.fetch(element.base_type, "element")
          end

          def boundary_role(boundary)
            BOUNDARY_ROLES.fetch(boundary.boundary_type, "boundary")
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
          private_class_method :graph_contents, :graph_attributes,
                               :identity_map, :entity_nodes, :boundary_nodes,
                               :element_nodes, :source_index, :boundary_node,
                               :boundary_values, :element_node,
                               :element_values, :relationships,
                               :relationship_record, :relationship_values,
                               :relationship_details, :relationship_edge,
                               :relationship_attributes,
                               :relationship_properties, :relationship_role,
                               :settings_nodes,
                               :semantic_nodes, :element_role, :boundary_role,
                               :reserve_id
        end
      end
    end
  end
end
