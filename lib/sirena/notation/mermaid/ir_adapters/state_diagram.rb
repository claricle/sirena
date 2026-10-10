# frozen_string_literal: true

require_relative "../../../ir"

module Sirena
  module Notation
    module Mermaid
      module IRAdapters
        # Maps Mermaid's private StateDiagram model to a notation-neutral graph.
        module StateDiagram
          STATE_ROLES = {
            "start" => "initial_state",
            "end" => "final_state",
            "choice" => "choice_state",
            "fork" => "fork_state",
            "join" => "join_state",
          }.freeze
          private_constant :STATE_ROLES

          module_function

          def call(diagram)
            occupied = []
            nodes, edges = graph_contents(diagram, occupied)
            IR::Graph.new(**graph_attributes(
              diagram, nodes, edges, occupied
            ))
          end

          def graph_contents(diagram, occupied)
            entries = state_entries(diagram.states)
            identities = state_identities(entries, occupied)
            states = state_nodes(entries, identities, occupied)
            details, transitions = transition_records(
              diagram.transitions, entries, identities, occupied
            )
            settings = settings_nodes(diagram, occupied)
            [states + details + settings, transitions]
          end

          def state_entries(states, parent = nil)
            Array(states).flat_map do |state|
              [[state, parent], *state_entries(state.children, state)]
            end
          end

          def state_identities(entries, occupied)
            identities = {}.compare_by_identity
            entries.each_with_index.with_object(identities) do |entry, result|
              (state, _parent), index = entry
              preferred = state.id.to_s.empty? ? "state_#{index}" : state.id
              result[state] = reserve_id(preferred, occupied)
            end
          end

          def state_nodes(entries, identities, occupied)
            entries.flat_map.with_index do |(state, parent), index|
              state_record(state, parent, index, identities, occupied)
            end
          end

          def state_record(state, parent, index, identities, occupied)
            id = identities.fetch(state)
            entity = IR::Node.new(
              id: id, label: state.label, role: state_role(state.state_type),
              parent_id: identities[parent]
            )
            values = state_values(state, index)
            [entity, *semantic_nodes(id, values, occupied)]
          end

          def state_values(state, index)
            values = [["original_identifier", state.id],
                      ["declared_state_type", state.state_type],
                      ["latest_description", state.description],
                      ["sequence_index", index]]
            values + Array(state.descriptions).map do |description|
              ["display_text", description]
            end
          end

          def state_role(state_type)
            STATE_ROLES.fetch(state_type, "state")
          end

          def transition_records(transitions, entries, identities, occupied)
            endpoints = source_index(entries, identities)
            records = Array(transitions).map.with_index do |transition, index|
              transition_record(transition, index, endpoints, occupied)
            end
            [records.flat_map(&:first), records.map(&:last)]
          end

          def source_index(entries, identities)
            entries.each_with_object({}) do |(state, _parent), index|
              index[state.id] ||= identities.fetch(state)
            end
          end

          def transition_record(transition, index, endpoints, occupied)
            details_id = reserve_id("transition_#{index}_details", occupied)
            details = transition_details(
              transition, index, details_id, occupied
            )
            edge = transition_edge(
              transition, index, details_id, endpoints, occupied
            )
            [details, edge]
          end

          def transition_details(transition, index, details_id, occupied)
            values = [
              ["trigger", transition.trigger],
              ["guard_condition", transition.guard_condition],
              ["transition_identifier",
               "#{transition.from_id}_to_#{transition.to_id}"],
              ["sequence_index", index],
            ]
            [
              IR::Node.new(id: details_id, role: "transition_details"),
              *semantic_nodes(details_id, values, occupied),
            ]
          end

          def transition_edge(transition, index, details_id, endpoints,
                              occupied)
            IR::Edge.new(
              id: reserve_id("transition_#{index}", occupied),
              label: transition.label, role: "state_transition",
              parent_id: details_id,
              source_id: endpoints[transition.from_id],
              target_id: endpoints[transition.to_id],
              properties: IR::PropertySet.new(target_marker: "arrow")
            )
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

              IR::Node.new(
                id: reserve_id("#{parent_id}_#{role}", occupied),
                label: value.to_s, role: role, parent_id: parent_id
              )
            end
          end

          def graph_attributes(diagram, nodes, edges, occupied)
            {
              id: reserve_id(diagram.id || "state_diagram", occupied),
              label: diagram.title, role: "state_machine",
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
          private_class_method :graph_contents, :state_entries,
                               :state_identities, :state_nodes, :state_record,
                               :state_values, :state_role,
                               :transition_records, :source_index,
                               :transition_record, :transition_details,
                               :transition_edge, :settings_nodes,
                               :semantic_nodes, :graph_attributes,
                               :optional_value, :reserve_id
        end
      end
    end
  end
end
