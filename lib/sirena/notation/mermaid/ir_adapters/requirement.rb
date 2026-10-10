# frozen_string_literal: true

require_relative "../../../ir"

module Sirena
  module Notation
    module Mermaid
      module IRAdapters
        # Maps Mermaid's private Requirement model to a notation-neutral graph.
        module Requirement
          REQUIREMENT_TYPES = {
            "requirement" => "requirement",
            "functionalRequirement" => "functional_requirement",
            "interfaceRequirement" => "interface_requirement",
            "performanceRequirement" => "performance_requirement",
            "physicalRequirement" => "physical_requirement",
            "designConstraint" => "design_constraint",
          }.freeze
          private_constant :REQUIREMENT_TYPES

          module_function

          def call(diagram)
            occupied = []
            entities, ids_by_name = entity_nodes(diagram, occupied)
            semantics = semantic_nodes(diagram, entities, occupied)
            style_nodes = style_nodes(diagram, occupied)
            nodes = entities + semantics + style_nodes
            root_id = reserve_id(diagram.id || "requirement_graph", occupied)
            edges = relationship_edges(
              diagram.relationships, ids_by_name, occupied
            )
            IR::Graph.new(**graph_attributes(diagram, root_id, nodes, edges))
          end

          def entity_nodes(diagram, occupied)
            entries = entity_entries(diagram)
            nodes = entries.map do |entity, role|
              entity_node(entity, role, occupied)
            end
            [nodes, source_ids(entries, nodes)]
          end

          def entity_entries(diagram)
            requirements = diagram.requirements.map do |requirement|
              [requirement, "requirement"]
            end
            elements = diagram.elements.map { |element| [element, "element"] }
            requirements + elements
          end

          def entity_node(entity, role, occupied)
            IR::Node.new(
              id: reserve_id(entity.name, occupied),
              label: entity.name, role: role
            )
          end

          def source_ids(entries, nodes)
            entries.zip(nodes).to_h do |(entity, _role), node|
              [entity.name, node.id]
            end
          end

          def semantic_nodes(diagram, entities, occupied)
            entity_index = 0
            diagram.requirements.flat_map do |requirement|
              parent_id = entities.fetch(entity_index).id
              entity_index += 1
              requirement_semantics(requirement, parent_id, occupied)
            end + diagram.elements.flat_map do |element|
              parent_id = entities.fetch(entity_index).id
              entity_index += 1
              element_semantics(element, parent_id, occupied)
            end
          end

          def requirement_semantics(requirement, parent_id, occupied)
            values = [
              ["requirement_type",
               normalized_requirement_type(requirement.type)],
              ["external_identifier", requirement.id],
              ["description", requirement.text],
              ["risk", requirement.risk],
              ["verification_method", requirement.verifymethod],
            ]
            semantic_values(values, parent_id, occupied) +
              style_references(requirement.classes, parent_id, occupied)
          end

          def element_semantics(element, parent_id, occupied)
            values = [
              ["element_type", element.type],
              ["document_reference", element.docref],
            ]
            semantic_values(values, parent_id, occupied) +
              style_references(element.classes, parent_id, occupied)
          end

          def semantic_values(values, parent_id, occupied)
            values.filter_map do |role, value|
              semantic_node(parent_id, role, value, occupied) unless value.nil?
            end
          end

          def style_references(classes, parent_id, occupied)
            classes.map do |class_name|
              semantic_node(parent_id, "style_reference", class_name, occupied)
            end
          end

          def style_nodes(diagram, occupied)
            inline_styles(diagram.styles, occupied) +
              class_definitions(diagram.classes, occupied) +
              class_assignments(diagram.class_assignments, occupied)
          end

          def inline_styles(styles, occupied)
            styles.flat_map.with_index do |style, index|
              container_id = reserve_id("inline_style_#{index}", occupied)
              [IR::Node.new(id: container_id, role: "inline_style")] +
                style_details(style, container_id, occupied)
            end
          end

          def class_definitions(classes, occupied)
            classes.flat_map.with_index do |klass, index|
              container_id = reserve_id("style_class_#{index}", occupied)
              [IR::Node.new(
                id: container_id, label: klass.name, role: "style_class",
              )] + style_properties(klass, container_id, occupied)
            end
          end

          def class_assignments(assignments, occupied)
            assignments.flat_map.with_index do |assignment, index|
              container_id = reserve_id("style_assignment_#{index}", occupied)
              [IR::Node.new(id: container_id, role: "style_assignment")] +
                assignment_details(assignment, container_id, occupied)
            end
          end

          def style_details(style, parent_id, occupied)
            references(
              style.target_ids, parent_id, "target_reference", occupied
            ) +
              style_properties(style, parent_id, occupied)
          end

          def style_properties(style, parent_id, occupied)
            values = [
              ["fill_color", style.fill],
              ["stroke_color", style.stroke],
              ["stroke_width", style.stroke_width],
            ]
            semantic_values(values, parent_id, occupied) +
              references(
                style.properties, parent_id, "style_property", occupied
              )
          end

          def assignment_details(assignment, parent_id, occupied)
            references(
              assignment.target_ids, parent_id, "target_reference", occupied
            ) + references(
              assignment.class_names, parent_id, "style_reference", occupied
            )
          end

          def references(values, parent_id, role, occupied)
            values.map do |value|
              semantic_node(parent_id, role, value, occupied)
            end
          end

          def semantic_node(parent_id, role, value, occupied)
            IR::Node.new(
              id: reserve_id("#{parent_id}_#{role}", occupied),
              label: value, role: role, parent_id: parent_id
            )
          end

          def relationship_edges(relationships, ids_by_name, occupied)
            relationships.filter_map.with_index do |relationship, index|
              source_id = ids_by_name[relationship.source]
              target_id = ids_by_name[relationship.target]
              next unless source_id && target_id

              IR::Edge.new(
                id: reserve_id("relationship_#{index}", occupied),
                source_id: source_id, target_id: target_id,
                role: relationship.type
              )
            end
          end

          def graph_attributes(diagram, root_id, nodes, edges)
            {
              id: root_id, label: diagram.title, role: "requirement_graph",
              accessibility_title: diagram.acc_title,
              accessibility_description: diagram.acc_description,
              nodes: nodes, edges: edges
            }
          end

          def normalized_requirement_type(type)
            REQUIREMENT_TYPES.fetch(type, type)
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
          private_class_method :entity_nodes, :entity_entries, :entity_node,
                               :source_ids, :semantic_nodes,
                               :requirement_semantics, :element_semantics,
                               :semantic_values, :style_references,
                               :style_nodes, :inline_styles,
                               :class_definitions, :class_assignments,
                               :style_details, :style_properties,
                               :assignment_details, :references,
                               :semantic_node, :relationship_edges,
                               :graph_attributes, :normalized_requirement_type,
                               :reserve_id
        end
      end
    end
  end
end
