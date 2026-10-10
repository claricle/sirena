# frozen_string_literal: true

require_relative "../../../ir"

module Sirena
  module Notation
    module Mermaid
      module IRAdapters
        # Maps the private ER diagram model to a notation-neutral graph.
        module ErDiagram
          module_function

          def call(diagram)
            occupied = []
            nodes, edges = graph_contents(diagram, occupied)
            IR::Graph.new(**graph_attributes(
              diagram, nodes, edges, occupied
            ))
          end

          def graph_contents(diagram, occupied)
            identities = entity_identities(diagram.entities, occupied)
            entities = entity_nodes(diagram.entities, identities, occupied)
            details, edges = relationship_records(
              diagram.relationships, identities, occupied
            )
            styles = style_nodes(class_definitions(diagram), occupied)
            settings = settings_nodes(diagram, occupied)
            [entities + details + styles + settings, edges]
          end

          def class_definitions(diagram)
            # The accessor initializes an ivar; query a copy to remain pure.
            diagram.dup.class_defs
          end

          def entity_identities(entities, occupied)
            entities.each_with_index
              .with_object({}.compare_by_identity) do |entry, identities|
              entity, index = entry
              preferred = entity.id.to_s.empty? ? "entity_#{index}" : entity.id
              identities[entity] = reserve_id(preferred, occupied)
            end
          end

          def entity_nodes(entities, identities, occupied)
            entities.flat_map.with_index do |entity, index|
              entity_record(entity, index, identities.fetch(entity), occupied)
            end
          end

          def entity_record(entity, index, id, occupied)
            node = IR::Node.new(id: id, label: entity.name, role: "entity")
            values = [["original_identifier", entity.id],
                      ["sequence_index", index]]
            semantics = semantic_nodes(id, values, occupied)
            classes = semantic_values(
              id, "style_reference", entity.classes, occupied
            )
            attributes = attribute_nodes(entity.attributes, id, occupied)
            [node, *semantics, *classes, *attributes]
          end

          def attribute_nodes(attributes, parent_id, occupied)
            attributes.map.with_index.flat_map do |attribute, index|
              attribute_record(attribute, index, parent_id, occupied)
            end
          end

          def attribute_record(attribute, index, parent_id, occupied)
            id = reserve_id("#{parent_id}_attribute_#{index}", occupied)
            node = IR::Node.new(
              id: id, label: attribute.name, role: "attribute",
              parent_id: parent_id
            )
            values = [
              ["attribute_type", attribute.attribute_type],
              ["key_type", attribute.key_type], ["note", attribute.note],
              ["sequence_index", index]
            ]
            [node, *semantic_nodes(id, values, occupied)]
          end

          def relationship_records(relationships, identities, occupied)
            endpoints = source_index(identities)
            records = relationships.filter_map.with_index do |relation, index|
              relationship_record(relation, index, endpoints, occupied)
            end
            [records.flat_map(&:first), records.map(&:last)]
          end

          def relationship_record(relation, index, endpoints, occupied)
            ids = [endpoints[relation.from_id], endpoints[relation.to_id]]
            return unless ids.all?

            detail_id = reserve_id("relationship_#{index}_details", occupied)
            details = relationship_details(relation, index, detail_id, occupied)
            edge = relationship_edge(relation, index, detail_id, ids, occupied)
            [details, edge]
          end

          def relationship_details(relationship, index, id, occupied)
            values = [
              ["relationship_type", relationship.relationship_type],
              ["source_cardinality", relationship.cardinality_from],
              ["target_cardinality", relationship.cardinality_to],
              ["sequence_index", index],
            ]
            [IR::Node.new(id: id, role: "relationship_details"),
             *semantic_nodes(id, values, occupied)]
          end

          def relationship_edge(relationship, index, details_id, endpoints,
                                occupied)
            IR::Edge.new(
              id: reserve_id("relationship_#{index}", occupied),
              label: relationship.label, role: relationship_role(relationship),
              parent_id: details_id, source_id: endpoints.first,
              target_id: endpoints.last,
              properties: relationship_properties(relationship)
            )
          end

          def relationship_properties(relationship)
            IR::PropertySet.new(
              source_marker: relationship.cardinality_from,
              target_marker: relationship.cardinality_to,
            )
          end

          def relationship_role(relationship)
            return "identifying_relationship" if relationship.identifying?

            "non_identifying_relationship"
          end

          def style_nodes(class_defs, occupied)
            class_defs.flat_map.with_index do |(name, declaration), index|
              id = reserve_id("style_class_#{index}", occupied)
              node = IR::Node.new(id: id, label: name, role: "style_class")
              values = [["style_declaration", declaration],
                        ["sequence_index", index]]
              [node, *semantic_nodes(id, values, occupied)]
            end
          end

          def settings_nodes(diagram, occupied)
            id = reserve_id("diagram_settings", occupied)
            values = [
              ["diagram_identifier", diagram.id],
              ["layout_direction", diagram.direction],
              ["theme_reference", diagram.theme],
            ]
            [IR::Node.new(id: id, role: "diagram_settings"),
             *semantic_nodes(id, values, occupied)]
          end

          def semantic_nodes(parent_id, values, occupied)
            values.filter_map do |role, value|
              next if value.nil?

              semantic_node(parent_id, role, value, occupied)
            end
          end

          def semantic_values(parent_id, role, values, occupied)
            values.map do |value|
              semantic_node(parent_id, role, value, occupied)
            end
          end

          def semantic_node(parent_id, role, value, occupied)
            IR::Node.new(
              id: reserve_id("#{parent_id}_#{role}", occupied),
              label: value.to_s, role: role, parent_id: parent_id
            )
          end

          def source_index(identities)
            identities.each_with_object({}) do |(entity, id), index|
              index[entity.id] ||= id
            end
          end

          def graph_attributes(diagram, nodes, edges, occupied)
            {
              id: reserve_id(diagram.id || "er_diagram", occupied),
              label: diagram.title, role: "entity_relationship_graph",
              nodes: nodes, edges: edges
            }
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
          private_class_method :graph_contents, :class_definitions,
                               :entity_identities,
                               :entity_nodes,
                               :entity_record, :attribute_nodes,
                               :attribute_record, :relationship_records,
                               :relationship_record, :relationship_details,
                               :relationship_edge, :relationship_properties,
                               :relationship_role,
                               :style_nodes, :settings_nodes, :semantic_nodes,
                               :semantic_values, :semantic_node, :source_index,
                               :graph_attributes, :reserve_id
        end
      end
    end
  end
end
