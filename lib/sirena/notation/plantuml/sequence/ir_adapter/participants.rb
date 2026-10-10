# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Sequence
        module IRAdapter
          # Encodes the lifelines and the boxes round neighbouring ones.
          module Participants
            module_function

            # @return [Hash{String => IR::Node}] participant node by id
            def call(diagram, sink)
              ids = diagram.participants.to_h do |participant|
                [participant.id, participant(participant, sink)]
              end
              diagram.boxes.each { |box| box(box, sink, ids) }
              ids
            end

            def participant(participant, sink)
              node = sink.node(participant.kind.to_s, participant.label)
              sink.detail(node, "name", participant.id)
              sink.detail(node, "stereotype", participant.stereotype)
              Fills.call(node, participant.fill, sink)
              node
            end

            def box(box, sink, ids)
              node = sink.node("box", box.title)
              box.members.each do |member|
                sink.edge("box_member", node, ids.fetch(member),
                          parent_id: node.id)
              end
            end
          end
        end
      end
    end
  end
end
