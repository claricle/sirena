# frozen_string_literal: true

require_relative "../../../ir"

module Sirena
  module Notation
    module Mermaid
      module IRAdapters
        # Maps Mermaid's private Class Diagram model to a neutral graph.
        module ClassDiagram
          MARKERS = {
            "inheritance" => "triangle",
            "composition" => "filled_diamond",
            "aggregation" => "hollow_diamond",
            "dependency" => "arrow",
            "realization" => "triangle",
          }.freeze
          private_constant :MARKERS

          module_function

          def call(diagram)
            occupied = []
            entities = entity_records(diagram.entities, occupied)
            nodes, edges = graph_contents(diagram, entities, occupied)
            IR::Graph.new(**graph_attributes(diagram, nodes, edges, occupied))
          end

          def graph_contents(diagram, entities, occupied)
            nodes = entities.flat_map do |entity, id|
              entity_record(entity, id, occupied)
            end
            relationship_nodes, edges = relationship_records(
              Array(diagram.relationships), entities, occupied
            )
            nodes += relationship_nodes +
              settings_nodes(diagram, occupied)
            [nodes, edges]
          end

          def graph_attributes(diagram, nodes, edges, occupied)
            {
              id: reserve_id(diagram.id || "class_diagram", occupied),
              label: diagram.title, role: "class_graph",
              nodes: nodes, edges: edges
            }
          end

          def entity_records(entities, occupied)
            entities.each_with_index.map do |entity, index|
              preferred = entity.id.to_s.empty? ? "class_#{index}" : entity.id
              [entity, reserve_id(preferred, occupied)]
            end
          end

          def entity_record(entity, id, occupied)
            node = IR::Node.new(id: id, label: entity.name, role: "class")
            fields = semantic_nodes(
              id,
              [["original_identifier", entity.id],
               ["stereotype", entity.stereotype]],
              occupied,
            )
            members = member_records(entity, id, occupied)
            [node, *fields, *members]
          end

          def member_records(entity, parent_id, occupied)
            attributes = records_for(
              entity.attributes, parent_id, "attribute", occupied
            )
            methods = records_for(
              entity.class_methods, parent_id, "operation", occupied
            )
            attributes + methods
          end

          def records_for(members, parent_id, role, occupied)
            members.flat_map.with_index do |member, index|
              member_record(member, parent_id, role, index, occupied)
            end
          end

          def member_record(member, parent_id, role, index, occupied)
            id = reserve_id("#{parent_id}_#{role}_#{index}", occupied)
            node = IR::Node.new(
              id: id, label: member.display_text, role: role,
              parent_id: parent_id
            )
            [node, *semantic_nodes(id, member_values(member, role), occupied)]
          end

          def member_values(member, role)
            return attribute_values(member) if role == "attribute"

            operation_values(member)
          end

          def attribute_values(attribute)
            [["name", attribute.name], ["type", attribute.type],
             ["visibility", attribute.visibility],
             ["source_text", attribute.text]]
          end

          def operation_values(operation)
            [["name", operation.name], ["parameters", operation.parameters],
             ["return_type", operation.return_type],
             ["visibility", operation.visibility],
             ["source_text", operation.text]]
          end

          def relationship_records(relationships, entities, occupied)
            endpoints = endpoint_index(entities)
            records = relationships.map.with_index do |relationship, index|
              relationship_record(
                relationship, index, endpoints, occupied
              )
            end
            [records.flat_map(&:first), records.map(&:last)]
          end

          def endpoint_index(entities)
            entities.each_with_object({}) do |(entity, id), index|
              index[entity.id] ||= id
            end
          end

          def relationship_record(relationship, index, endpoints, occupied)
            detail_id = reserve_id("relationship_details_#{index}", occupied)
            details = relationship_details(relationship, detail_id, occupied)
            edge = relationship_edge(
              relationship, index, detail_id, endpoints, occupied
            )
            [details, edge]
          end

          def relationship_edge(relationship, index, detail_id, endpoints,
                                occupied)
            IR::Edge.new(
              id: reserve_id("relationship_#{index}", occupied),
              label: relationship.label, role: "class_relationship",
              parent_id: detail_id,
              source_id: endpoints[relationship.from_id],
              target_id: endpoints[relationship.to_id],
              properties: relationship_properties(relationship)
            )
          end

          def relationship_details(relationship, id, occupied)
            node = IR::Node.new(id: id, role: "relationship_details")
            values = [
              ["relationship_type", relationship.relationship_type],
              ["source_cardinality", relationship.source_cardinality],
              ["target_cardinality", relationship.target_cardinality],
              ["source_marker", relationship.start_marker],
              ["target_marker", relationship.end_marker],
              ["dashed", relationship.dashed],
            ]
            [node, *semantic_nodes(id, values, occupied)]
          end

          def relationship_properties(relationship)
            source, target = explicit_markers(relationship)
            if source.nil? && target.nil?
              source, target = implied_markers(relationship.relationship_type)
            end
            IR::PropertySet.new(source_marker: source, target_marker: target)
          end

          def explicit_markers(relationship)
            [MARKERS[relationship.start_marker],
             MARKERS[relationship.end_marker]]
          end

          def implied_markers(type)
            marker = MARKERS[type]
            return [marker, nil] if %w[composition aggregation].include?(type)

            [nil, marker]
          end

          def settings_nodes(diagram, occupied)
            id = reserve_id("diagram_settings", occupied)
            values = [
              ["diagram_identifier", diagram.id],
              ["layout_direction", diagram.direction],
              ["theme", diagram.theme],
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

          def reserve_id(preferred, occupied)
            preferred = preferred.to_s
            preferred = "item" if preferred.empty?
            candidate = unique_id(preferred, occupied)
            occupied << candidate
            candidate
          end

          def unique_id(preferred, occupied)
            return preferred unless occupied.include?(preferred)

            suffix = 2
            suffix += 1 while occupied.include?("#{preferred}_#{suffix}")
            "#{preferred}_#{suffix}"
          end
          private_class_method :graph_contents, :graph_attributes,
                               :entity_records, :entity_record,
                               :member_records, :records_for, :member_record,
                               :member_values,
                               :attribute_values, :operation_values,
                               :relationship_records, :endpoint_index,
                               :relationship_record, :relationship_edge,
                               :relationship_details,
                               :relationship_properties, :explicit_markers,
                               :implied_markers, :settings_nodes,
                               :semantic_nodes, :reserve_id, :unique_id
        end
      end
    end
  end
end
