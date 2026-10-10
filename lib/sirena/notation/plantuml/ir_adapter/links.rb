# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module IRAdapter
        # Encodes relations, association classes and note attachments as
        # edges between the class nodes.
        module Links
          module_function

          # @param ids [Hash{String => IR::Node}] class node by class name
          def call(diagram, sink, ids)
            diagram.relations.each { |rel| relation(rel, sink, ids) }
            diagram.junctions.each { |junction| junction(junction, sink, ids) }
            diagram.notes.each { |note| note(note, sink, ids) }
          end

          def relation(relation, sink, ids)
            attributes = relation_attributes(relation, sink)
            attributes[:properties] = markers(relation)
            attributes[:label] = relation.label
            sink.edge(relation.kind&.to_s, ids.fetch(relation.left),
                      ids.fetch(relation.right), **attributes)
          end

          def markers(relation)
            IR::PropertySet.new(
              source_marker: relation.markers[:left]&.to_s,
              target_marker: relation.markers[:right]&.to_s,
            )
          end

          # The relation facts an edge has no field for hang off one node.
          def relation_attributes(relation, sink)
            details = relation_details(relation)
            return {} if details.empty?

            node = sink.node("relation_attributes")
            details.each { |role, value| sink.detail(node, role, value) }
            { parent_id: node.id }
          end

          def relation_details(relation)
            {
              "left_multiplicity" => relation.left_multiplicity,
              "right_multiplicity" => relation.right_multiplicity,
              "left_role" => relation.left_role,
              "right_role" => relation.right_role,
              "dashed" => ("true" if relation.dashed?),
              "plain" => ("true" if relation.plain?),
            }.compact
          end

          def junction(junction, sink, ids)
            node = sink.node("association_class")
            [junction.from, junction.to].each do |name|
              sink.edge("association_end", node, ids.fetch(name))
            end
            sink.edge("association_owner", node, ids.fetch(junction.owner))
          end

          def note(note, sink, ids)
            node = sink.node("note")
            sink.detail(node, "side", note.side)
            sink.detail(node, "member", note.member)
            sink.detail(node, "color", note.color)
            sink.detail(node, "stereotype", note.stereotype)
            sink.details(node, "line", note.lines)
            sink.edge("note_link", node, ids.fetch(note.target))
          end
        end
      end
    end
  end
end
