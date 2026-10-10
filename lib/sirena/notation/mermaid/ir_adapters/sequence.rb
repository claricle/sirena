# frozen_string_literal: true

require_relative "../../../ir"

module Sirena
  module Notation
    module Mermaid
      module IRAdapters
        # Maps Mermaid's private Sequence model to a notation-neutral graph.
        module Sequence
          module_function

          def call(diagram)
            occupied = []
            nodes, edges = graph_contents(diagram, occupied)
            IR::Graph.new(**graph_attributes(
              diagram, nodes, edges, occupied
            ))
          end

          def graph_contents(diagram, occupied)
            participants = participant_identities(diagram, occupied)
            contents = event_contents(diagram, participants, occupied)
            nodes = participant_nodes(diagram, participants, occupied)
            nodes += contents.flat_map(&:first)
            nodes += settings_nodes(diagram, occupied)
            [nodes, contents.flat_map(&:last)]
          end

          def event_contents(diagram, participants, occupied)
            [messages(diagram, participants, occupied),
             notes(diagram, participants, occupied),
             activations(diagram, participants, occupied),
             frames(diagram, occupied),
             boxes(diagram, participants, occupied)]
          end

          def participant_identities(diagram, occupied)
            participants = Array(diagram.participants)
            participants.each_with_index.to_h do |participant, index|
              preferred = participant.id.to_s
              preferred = "participant_#{index}" if preferred.empty?
              [participant, reserve_id(preferred, occupied)]
            end
          end

          def participant_nodes(diagram, identities, occupied)
            participants = Array(diagram.participants)
            participants.flat_map.with_index do |participant, index|
              id = identities.fetch(participant)
              entity = IR::Node.new(
                id: id, label: participant.label,
                role: participant_role(participant.actor_type)
              )
              values = [
                ["original_identifier", participant.id],
                ["participant_type", participant.actor_type],
                ["sequence_index", index],
              ]
              [entity, *semantic_nodes(id, values, occupied)]
            end
          end

          def participant_role(actor_type)
            actor_type == "actor" ? "actor" : "participant"
          end

          def messages(diagram, participant_ids, occupied)
            endpoints = source_index(Array(diagram.participants),
                                     participant_ids)
            records = Array(diagram.messages).map.with_index do |message, index|
              message_record(message, index, endpoints, occupied)
            end
            [records.flat_map(&:first), records.map(&:last)]
          end

          def source_index(participants, identities)
            participants.each_with_object({}) do |participant, index|
              index[participant.id] ||= identities.fetch(participant)
            end
          end

          def message_record(message, index, endpoints, occupied)
            detail_id = reserve_id("message_#{index}_details", occupied)
            details = message_details(message, index, detail_id, occupied)
            edge = message_edge(message, index, detail_id, endpoints, occupied)
            [details, edge]
          end

          def message_details(message, index, detail_id, occupied)
            values = [
              ["line_style", message.line_style],
              ["head_style", message.head_style],
              ["head_side", message.head_side],
              ["sequence_index", index],
            ]
            [IR::Node.new(id: detail_id, role: "message_details"),
             *semantic_nodes(detail_id, values, occupied)]
          end

          def message_edge(message, index, detail_id, endpoints, occupied)
            IR::Edge.new(
              id: reserve_id("message_#{index}", occupied),
              label: message.message_text, role: "message",
              parent_id: detail_id,
              source_id: endpoints[message.from_id],
              target_id: endpoints[message.to_id]
            )
          end

          def notes(diagram, participant_ids, occupied)
            endpoints = source_index(Array(diagram.participants),
                                     participant_ids)
            records = Array(diagram.notes).map.with_index do |note, index|
              note_record(note, index, endpoints, occupied)
            end
            [records.flat_map(&:first), records.flat_map(&:last)]
          end

          def note_record(note, index, endpoints, occupied)
            note_id = reserve_id("note_#{index}", occupied)
            values = [["note_position", note.position],
                      ["message_index", note.message_index],
                      ["order", note.order]]
            nodes = [IR::Node.new(
              id: note_id, label: note.text, role: "note",
            ), *semantic_nodes(note_id, values, occupied)]
            [nodes, note_references(note, index, note_id, endpoints, occupied)]
          end

          def note_references(note, index, note_id, endpoints, occupied)
            note.participant_ids.map.with_index do |participant_id, ref_index|
              reference_edge(
                "note_reference_#{index}_#{ref_index}", "note_reference",
                note_id, endpoints[participant_id], occupied
              )
            end
          end

          def activations(diagram, participant_ids, occupied)
            endpoints = source_index(Array(diagram.participants),
                                     participant_ids)
            entries = Array(diagram.activations)
            records = entries.map.with_index do |activation, index|
              activation_record(activation, index, endpoints, occupied)
            end
            [records.flat_map(&:first), records.map(&:last)]
          end

          def activation_record(activation, index, endpoints, occupied)
            activation_id = reserve_id("activation_#{index}", occupied)
            values = [["start_index", activation.start_index],
                      ["end_index", activation.end_index]]
            nodes = [IR::Node.new(id: activation_id, role: "activation"),
                     *semantic_nodes(activation_id, values, occupied)]
            edge = reference_edge(
              "activation_reference_#{index}", "activation_reference",
              activation_id, endpoints[activation.participant_id], occupied
            )
            [nodes, edge]
          end

          def frames(diagram, occupied)
            records = Array(diagram.frames).map.with_index do |frame, index|
              frame_record(frame, index, occupied)
            end
            [records.flatten(1), []]
          end

          def frame_record(frame, index, occupied)
            id = reserve_id("frame_#{index}", occupied)
            values = [["frame_kind", frame.kind],
                      ["start_index", frame.start_index],
                      ["end_index", frame.end_index],
                      ["depth", frame.depth],
                      ["open_order", frame.open_order],
                      ["close_order", frame.close_order]]
            nodes = [IR::Node.new(id: id, label: frame.label, role: "frame"),
                     *semantic_nodes(id, values, occupied)]
            nodes + section_nodes(frame, id, occupied)
          end

          def section_nodes(frame, frame_id, occupied)
            Array(frame.sections).flat_map.with_index do |section, index|
              id = reserve_id("#{frame_id}_section_#{index}", occupied)
              values = [["section_kind", section.kind],
                        ["start_index", section.start_index],
                        ["order", section.order],
                        ["owner_frame", frame_id]]
              [IR::Node.new(id: id, label: section.label,
                            role: "frame_section"),
               *semantic_nodes(id, values, occupied)]
            end
          end

          def boxes(diagram, participant_ids, occupied)
            endpoints = source_index(Array(diagram.participants),
                                     participant_ids)
            records = Array(diagram.boxes).map.with_index do |box, index|
              box_record(box, index, endpoints, occupied)
            end
            [records.flat_map(&:first), records.flat_map(&:last)]
          end

          def box_record(box, index, endpoints, occupied)
            id = reserve_id("box_#{index}", occupied)
            nodes = [IR::Node.new(id: id, label: box.title, role: "box"),
                     *semantic_nodes(id, [["box_color", box.color]],
                                     occupied)]
            members = box.participant_ids.map.with_index do |member, ref|
              reference_edge("box_member_#{index}_#{ref}", "box_member",
                             id, endpoints[member], occupied)
            end
            [nodes, members]
          end

          def reference_edge(preferred, role, source_id, target_id, occupied)
            IR::Edge.new(
              id: reserve_id(preferred, occupied), role: role,
              source_id: source_id, target_id: target_id
            )
          end

          def settings_nodes(diagram, occupied)
            settings_id = reserve_id("diagram_settings", occupied)
            values = [
              ["diagram_identifier", diagram.id],
              ["layout_direction", diagram.direction],
              ["theme_reference", diagram.theme],
              ["autonumber", optional_value(diagram, :autonumber)],
              ["wrap", ("true" if diagram.wrap)],
            ]
            [IR::Node.new(id: settings_id, role: "diagram_settings"),
             *semantic_nodes(settings_id, values, occupied)]
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
              id: reserve_id(diagram.id || "sequence", occupied),
              label: diagram.title, role: "interaction_graph",
              accessibility_title: optional_value(diagram, :acc_title),
              accessibility_description: optional_value(
                diagram, :acc_description, :acc_descr
              ),
              nodes: nodes, edges: edges
            }
          end

          def optional_value(source, *names)
            names.each do |name|
              next unless source.respond_to?(name)

              value = source.public_send(name)
              return value unless value.nil?
            end
            nil
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
          private_class_method :graph_contents, :event_contents,
                               :participant_identities, :participant_nodes,
                               :participant_role, :messages, :source_index,
                               :message_record, :message_details,
                               :message_edge, :notes, :note_record,
                               :note_references, :activations,
                               :activation_record, :frames, :frame_record,
                               :section_nodes, :boxes, :box_record,
                               :reference_edge, :settings_nodes,
                               :semantic_nodes, :graph_attributes,
                               :optional_value, :reserve_id
        end
      end
    end
  end
end
