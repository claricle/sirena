# frozen_string_literal: true

require_relative "../../diagram/state_diagram"

module Sirena
  module Parser
    module Builders
      # Transform for converting Parslet parse tree to State diagram model.
      #
      # Converts the parse tree output from Grammars::StateDiagram into a
      # fully-formed Diagram::StateDiagram object with states and transitions.
      class StateDiagram
        # Special state markers
        START_END_MARKER = "[*]"

        # Transform parse tree into State diagram.
        #
        # @param tree [Array, Hash] Parslet parse tree
        # @return [Diagram::StateDiagram] the State diagram model
        def apply(tree)
          @diagram = Diagram::StateDiagram.new
          @state_counter = 0
          statements_in(tree).each { |item| process_item(item) }
          @diagram
        end

        private

        def statements_in(tree)
          return tree.grep(Hash) if tree.is_a?(Array)

          tree.is_a?(Hash) ? [tree] : []
        end

        def process_item(item)
          return unless item.is_a?(Hash)

          # Process a top-level direction statement
          if item[:direction] && item[:direction][:dir_value]
            @diagram.direction = extract_text(item[:direction][:dir_value])
          end

          # Process statements
          process_statement(item) unless item[:header] || item[:direction]
        end

        def process_statement(stmt)
          return unless stmt.is_a?(Hash)
          return process_state_declaration(stmt) if state_declaration?(stmt)
          return process_transition(stmt) if transition?(stmt)
          return if ignored_statement?(stmt)

          process_standalone_state(stmt) if standalone_state?(stmt)
        end

        def state_declaration?(stmt)
          stmt[:keyword] == "state" && stmt[:state_id]
        end

        def transition?(stmt)
          stmt[:from] && stmt[:to]
        end

        def standalone_state?(stmt)
          stmt[:state_id] && !stmt[:keyword]
        end

        # Notes and styles are parsed but dropped. This remains a parity gap:
        # mermaid renders note nodes, but the diagram model has nowhere to
        # carry them. A direction nested in a composite also falls through;
        # it cannot be attached to the model's flattened state collection.
        def ignored_statement?(stmt)
          stmt[:note_keyword] || stmt[:style_keyword]
        end

        def process_state_declaration(stmt)
          state_id = extract_text(stmt[:state_id])
          label = state_label(stmt)
          if stmt[:marker]
            declare_special_state(state_id, stmt[:marker])
          elsif stmt[:composite]
            declare_composite_state(state_id, label, stmt[:composite])
          else
            update_declared_state(state_id, label, description_of(stmt))
          end
        end

        # Marker states have no label because the model has no matching shape
        # for mermaid's labelled choice/fork/join declarations.
        def declare_special_state(state_id, marker)
          add_special_state(state_id, extract_text(marker[:marker_type]))
        end

        def declare_composite_state(state_id, label, composite)
          state = process_composite_state(state_id, label, composite)
          append_display_text(state, label)
        end

        def update_declared_state(state_id, label, description)
          state = add_or_update_state(state_id, label)
          append_display_text(state, label)
          return unless description

          state.description = description
          append_display_text(state, description)
        end

        # nil rather than "" when there is no description: every non-nil
        # value is recorded as display text.
        def description_of(stmt)
          extract_text(stmt[:description]) if stmt[:description]
        end

        def process_standalone_state(stmt)
          state_id = extract_text(stmt[:state_id])
          state = ensure_state_exists(state_id)
          return unless stmt[:description]

          description = extract_text(stmt[:description])
          state.description = description
          append_display_text(state, description)
        end

        # `state "Idle mode" as Idle` labels the state Idle "Idle mode";
        # without the alias the id is its own label.
        def state_label(stmt)
          return unless stmt[:state_label]

          label = extract_text(stmt[:state_label]).strip
          return if label.empty?

          label
        end

        def append_display_text(state, text)
          state.descriptions << text if text && !text.empty?
        end

        def process_transition(stmt)
          from_id = extract_state_id(stmt[:from], is_source: true)
          to_id = extract_state_id(stmt[:to], is_source: false)
          trigger, guard = parse_transition_label(stmt[:label])
          create_transition(from_id, to_id, trigger, guard)
          process_transition_chain(to_id, stmt[:chain])
        end

        def process_transition_chain(current_from, chain)
          Array(chain).each do |chain_item|
            next unless chain_item[:chain_to]

            chain_to = extract_state_id(chain_item[:chain_to], is_source: false)
            create_transition(current_from, chain_to)
            current_from = chain_to
          end
        end

        def process_composite_state(parent_id, label, composite_data)
          # Create parent state
          parent_state = add_or_update_state(parent_id, label)

          # Process nested statements
          if composite_data.is_a?(Hash) || composite_data.is_a?(Array)
            statements = Array(composite_data)
            statements.each do |stmt|
              next unless stmt.is_a?(Hash)

              process_statement(stmt)
            end
          end

          parent_state
        end

        # A marker is a start state as a source and an end state as a target.
        def extract_state_id(state_data, is_source: nil)
          state_str = extract_text(state_data)
          return state_str unless state_str.strip == START_END_MARKER

          is_source ? ensure_start_state : ensure_end_state
        end

        def ensure_start_state
          start_state = @diagram.start_state
          return start_state.id if start_state

          start_id = generate_state_id("start")
          state = Diagram::StateNode.new.tap do |s|
            s.id = start_id
            s.label = START_END_MARKER
            s.state_type = "start"
          end
          @diagram.states << state
          start_id
        end

        def ensure_end_state
          end_state = @diagram.end_states.first
          return end_state.id if end_state

          end_id = generate_state_id("end")
          state = Diagram::StateNode.new.tap do |s|
            s.id = end_id
            s.label = START_END_MARKER
            s.state_type = "end"
          end
          @diagram.states << state
          end_id
        end

        def ensure_state_exists(state_id)
          existing = @diagram.find_state(state_id)
          return existing if existing

          state = Diagram::StateNode.new.tap do |s|
            s.id = state_id
            s.label = state_id
            s.state_type = "normal"
          end
          @diagram.states << state
          state
        end

        def add_special_state(state_id, state_type)
          existing = @diagram.find_state(state_id)
          return existing if existing

          state = ensure_state_exists(state_id)
          state.label = nil
          state.state_type = state_type
          state
        end

        def add_or_update_state(state_id, label = nil)
          existing = @diagram.find_state(state_id)
          return update_state_label(existing, label) if existing

          state = build_state(state_id, label || state_id, "normal")
          @diagram.states << state
          state
        end

        def update_state_label(state, label)
          state.label = label if label && !label.empty?
          state
        end

        def build_state(id, label, type)
          Diagram::StateNode.new.tap do |state|
            state.id = id
            state.label = label
            state.state_type = type
          end
        end

        def create_transition(from_id, to_id, trigger = nil, guard = nil)
          # Ensure both states exist
          ensure_state_exists(from_id) unless from_id.start_with?("start_",
                                                                  "end_")
          ensure_state_exists(to_id) unless to_id.start_with?("start_", "end_")

          transition = Diagram::StateTransition.new.tap do |t|
            t.from_id = from_id
            t.to_id = to_id
            t.trigger = trigger
            t.guard_condition = guard
          end
          @diagram.transitions << transition
        end

        # Split "trigger [guard]" while preserving a trigger with no guard.
        def parse_transition_label(label_data)
          return [nil, nil] unless label_data

          label_text = extract_text(label_data[:label_text] || label_data).strip
          return [nil, nil] if label_text.empty?

          match = label_text.match(/^(.+?)\s*\[(.+?)\]\s*$/)
          return [label_text, nil] unless match

          [match[1].strip, match[2].strip]
        end

        def generate_state_id(prefix)
          @state_counter += 1
          "#{prefix}_#{@state_counter}"
        end

        def extract_text(value)
          return value.to_s unless value.is_a?(Hash)

          keys = %i[string marker_type dir_value label_text]
          key = keys.find { |name| value[name] }
          key ? value[key].to_s : value.values.first.to_s
        end
      end
    end
  end
end
