# frozen_string_literal: true

require_relative "../../../ir"

module Sirena
  module Notation
    module Mermaid
      module IRAdapters
        # Maps Mermaid's private Architecture model to a notation-neutral graph.
        module Architecture
          module_function

          def call(diagram)
            occupied = []
            identities = entity_identities(diagram, occupied)
            entities = entity_nodes(diagram, identities, occupied)
            details, edges = connection_records(diagram, identities, occupied)
            settings = settings_nodes(diagram, occupied)
            nodes = entities + details + settings
            IR::Graph.new(
              **graph_attributes(diagram, nodes, edges, occupied),
            )
          end

          def entity_identities(diagram, occupied)
            {
              groups: identity_map(diagram.groups, occupied, "group"),
              services: identity_map(diagram.services, occupied, "service"),
              junctions: identity_map(diagram.junctions, occupied, "junction"),
            }
          end

          def identity_map(items, occupied, fallback)
            items.each_with_index.to_h do |item, index|
              preferred = item.id.to_s.empty? ? "#{fallback}_#{index}" : item.id
              [item, reserve_id(preferred, occupied)]
            end
          end

          def entity_nodes(diagram, identities, occupied)
            group_index = source_index(diagram.groups, identities[:groups])
            group_nodes(diagram, identities, group_index, occupied) +
              member_nodes(diagram.services, "service", identities[:services],
                           group_index, occupied) +
              member_nodes(diagram.junctions, "junction",
                           identities[:junctions], group_index, occupied)
          end

          def group_nodes(diagram, identities, group_index, occupied)
            diagram.groups.flat_map do |group|
              group_node(group, identities[:groups], group_index, occupied)
            end
          end

          def member_nodes(members, role, identities, group_index, occupied)
            members.flat_map do |member|
              member_node(member, role, identities, group_index, occupied)
            end
          end

          def source_index(items, identities)
            items.each_with_object({}) do |item, index|
              index[item.id] ||= identities.fetch(item)
            end
          end

          def group_node(group, identities, group_index, occupied)
            id = identities.fetch(group)
            node = IR::Node.new(
              id: id, label: group.label, role: "group",
              parent_id: group_index[group.parent_id]
            )
            values = [
              ["original_identifier", group.id], ["icon", group.icon],
              ["parent_identifier", group.parent_id]
            ]
            [node, *semantic_nodes(id, values, occupied)]
          end

          def member_node(member, role, identities, group_index, occupied)
            id = identities.fetch(member)
            group_id = member.group_id
            node = IR::Node.new(
              id: id, label: member.respond_to?(:label) ? member.label : nil,
              role: role, parent_id: group_index[group_id]
            )
            values = [["original_identifier", member.id],
                      ["group_identifier", group_id]]
            values << ["icon", member.icon] if member.respond_to?(:icon)
            [node, *semantic_nodes(id, values, occupied)]
          end

          def connection_records(diagram, identities, occupied)
            endpoints = endpoint_index(diagram, identities)
            records = diagram.edges.filter_map.with_index do |edge, index|
              connection_record(edge, index, endpoints, occupied)
            end
            [records.flat_map(&:first), records.map(&:last)]
          end

          def endpoint_index(diagram, identities)
            nodes = diagram.services + diagram.junctions
            ids = identities[:services].merge(identities[:junctions])
            source_index(nodes, ids)
          end

          def connection_record(edge, index, endpoints, occupied)
            source_id = endpoints[edge.from_id]
            target_id = endpoints[edge.to_id]
            return unless source_id && target_id

            details_id = reserve_id("connection_details_#{index}", occupied)
            details = connection_details(edge, details_id, occupied)
            connection = IR::Edge.new(**connection_attributes(
              edge, index, details_id, [source_id, target_id], occupied
            ))
            [details, connection]
          end

          def connection_attributes(edge, index, details_id, endpoint_ids,
                                    occupied)
            source_id, target_id = endpoint_ids
            {
              id: reserve_id("connection_#{index}", occupied),
              label: edge.label, role: "directed_connection",
              parent_id: details_id, source_id: source_id,
              target_id: target_id,
              properties: IR::PropertySet.new(target_marker: "arrow")
            }
          end

          def connection_details(edge, details_id, occupied)
            node = IR::Node.new(id: details_id, role: "connection_details")
            values = [
              ["source_position", edge.from_position],
              ["target_position", edge.to_position],
            ]
            [node, *semantic_nodes(details_id, values, occupied)]
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

          def graph_attributes(diagram, nodes, edges, occupied)
            {
              id: reserve_id(diagram.id || "architecture", occupied),
              label: diagram.title, role: "architecture_graph",
              accessibility_title: diagram.acc_title,
              accessibility_description: diagram.acc_descr,
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
          private_class_method :entity_identities, :identity_map,
                               :entity_nodes, :group_nodes, :member_nodes,
                               :source_index, :group_node, :member_node,
                               :connection_records, :endpoint_index,
                               :connection_record, :connection_attributes,
                               :connection_details, :settings_nodes,
                               :semantic_nodes, :graph_attributes, :reserve_id
        end
      end
    end
  end
end
