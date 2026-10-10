# frozen_string_literal: true

require_relative "../junction"
require_relative "../note"
require_relative "../relation"

module Sirena
  module Notation
    module PlantUML
      module IRReader
        # Rebuilds the relations, association classes and notes from the
        # edges between class nodes.
        module Links
          NON_RELATION_ROLES = %w[
            association_end association_owner note_link
          ].freeze
          private_constant :NON_RELATION_ROLES

          module_function

          # @return [Array<Relation>] the edges that are relations
          def relations(index)
            relation_edges(index).map { |edge| relation(edge, index) }
          end

          # @return [Array<Junction>]
          def junctions(index)
            index.with_role("association_class").map do |node|
              junction(node, index)
            end
          end

          # @return [Array<Note>]
          def notes(index)
            index.with_role("note").map { |node| note(node, index) }
          end

          def relation_edges(index)
            index.edges.reject do |edge|
              NON_RELATION_ROLES.include?(edge.role)
            end
          end

          def relation(edge, index)
            node = edge.parent_id && index.node(edge.parent_id)
            Relation.new(
              left: name_of(edge.source_id, index),
              right: name_of(edge.target_id, index),
              arrow: arrow(edge, node, index),
              ends: ends(node, index), label: edge.label
            )
          end

          def arrow(edge, node, index)
            markers = markers(edge)
            { kind: edge.role&.to_sym, head: head(markers), markers: markers,
              dashed: flagged?(node, "dashed", index),
              plain: flagged?(node, "plain", index) }
          end

          def markers(edge)
            properties = edge.properties
            { left: properties.source_marker,
              right: properties.target_marker }.compact
              .transform_values(&:to_sym)
          end

          def head(markers)
            return :both if markers.size == 2

            markers.keys.first
          end

          def ends(node, index)
            {
              left: detail(node, "left_multiplicity", index),
              right: detail(node, "right_multiplicity", index),
              left_role: detail(node, "left_role", index),
              right_role: detail(node, "right_role", index),
            }
          end

          # A class is named by its label, a package by its source id.
          def name_of(node_id, index)
            node = index.node(node_id)
            return node.label unless node.role == "package"

            index.detail(node, "source_id")
          end

          def detail(node, role, index)
            node && index.detail(node, role)
          end

          def flagged?(node, role, index)
            !detail(node, role, index).nil?
          end

          def junction(node, index)
            ends = index.edges.select { |edge| edge.source_id == node.id }
            names = ends.map { |edge| name_of(edge.target_id, index) }
            Junction.new(from: names[0], to: names[1], owner: names[2])
          end

          def note(node, index)
            link = index.edges.find { |edge| edge.source_id == node.id }
            Note.new(note_head(node, link, index),
                     lines: index.details(node, "line").freeze)
          end

          def note_head(node, link, index)
            { side: index.detail(node, "side").to_sym,
              target: name_of(link.target_id, index),
              member: index.detail(node, "member"),
              color: index.detail(node, "color"),
              stereotype: index.detail(node, "stereotype") }
          end
        end
      end
    end
  end
end
