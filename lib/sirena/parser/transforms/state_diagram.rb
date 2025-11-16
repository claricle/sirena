# frozen_string_literal: true

require_relative '../../diagram/state_diagram'

module Sirena
  module Parser
    module Transforms
      # Transform for converting Parslet parse tree to State diagram model.
      #
      # Converts the parse tree output from Grammars::StateDiagram into a
      # fully-formed Diagram::StateDiagram object with states and transitions.
      class StateDiagram
        # Special state markers
        START_END_MARKER = '[*]'

        # Transform parse tree into State diagram.
        #
        # @param tree [Array, Hash] Parslet parse tree
        # @return [Diagram::StateDiagram] the State diagram model
        def apply(tree)
          @diagram = Diagram::StateDiagram.new
          @state_counter = 0

          # Tree is an array: [header, direction, ...statements]
          if tree.is_a?(Array)
            tree.each do |item|
              process_item(item) if item.is_a?(Hash)
            end
          elsif tree.is_a?(Hash)
            process_item(tree)
          end

          @diagram
        end

        private

        def process_item(item)
          return unless item.is_a?(Hash)

          # Process header to get direction
          if item[:direction] && item[:direction][:dir_value]
            @diagram.direction = extract_text(item[:direction][:dir_value])
          end

          # Process statements
          process_statement(item) unless item[:header] || item[:direction]
        end

        def process_statement(stmt)
          return unless stmt.is_a?(Hash)

          if stmt[:keyword] == 'state' && stmt[:state_id]
            # State declaration
            process_state_declaration(stmt)
          elsif stmt[:from] && stmt[:to]
            # Transition
            process_transition(stmt)
          elsif stmt[:note_keyword]
            # Note statement - skip for now
            nil
          elsif stmt[:state_id] && !stmt[:keyword]
            # Standalone state
            ensure_state_exists(extract_text(stmt[:state_id]))
          elsif stmt[:concurrent_sep]
            # Concurrent separator - handled in composite context
            nil
          end
        end

        def process_state_declaration(stmt)
          state_id = extract_text(stmt[:state_id])

          if stmt[:marker]
            # Special state marker (choice, fork, join)
            marker_type = extract_text(stmt[:marker][:marker_type])
            add_special_state(state_id, marker_type)
          elsif stmt[:composite]
            # Composite state with nested statements
            process_composite_state(state_id, stmt[:composite])
          elsif stmt[:description]
            # State with description
            description = extract_text(stmt[:description]).strip
            # Remove leading colon if present
            description = description.sub(/^:\s*/, '')
            add_or_update_state(state_id, state_id, description)
          else
            # Regular state
            ensure_state_exists(state_id)
          end
        end

        def process_transition(stmt)
          # Get source state (if [*], it's a start state)
          from_id = extract_state_id(stmt[:from], is_source: true)

          # Get target state (if [*], it's an end state)
          to_id = extract_state_id(stmt[:to], is_source: false)

          # Parse label for trigger and guard
          trigger, guard = parse_transition_label(stmt[:label])

          # Create transition
          create_transition(from_id, to_id, trigger, guard)

          # Handle chained transitions
          if stmt[:chain] && !stmt[:chain].empty?
            chain_transitions = Array(stmt[:chain])
            current_from = to_id

            chain_transitions.each do |chain_item|
              next unless chain_item[:chain_to]

              chain_to = extract_state_id(chain_item[:chain_to], is_source: false)
              create_transition(current_from, chain_to, nil, nil)
              current_from = chain_to
            end
          end
        end

        def process_composite_state(parent_id, composite_data)
          # Create parent state
          parent_state = add_or_update_state(parent_id, parent_id)

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

        def extract_state_id(state_data, is_source: nil)
          # Convert to string for comparison
          state_str = extract_text(state_data)

          # Check if this is a start/end marker
          if state_str == START_END_MARKER || state_str.strip == START_END_MARKER
            # If it's a source of transition, it's a start state
            # If it's a target of transition, it's an end state
            if is_source
              ensure_start_state
            else
              ensure_end_state
            end
          else
            state_str
          end
        end

        def ensure_start_or_end_state
          # Check if we already have a start state, if not create one
          # Otherwise create an end state
          start_state = @diagram.start_state
          if start_state
            ensure_end_state
          else
            ensure_start_state
          end
        end

        def ensure_start_state
          start_state = @diagram.start_state
          return start_state.id if start_state

          start_id = generate_state_id('start')
          state = Diagram::StateNode.new.tap do |s|
            s.id = start_id
            s.label = START_END_MARKER
            s.state_type = 'start'
          end
          @diagram.states << state
          start_id
        end

        def ensure_end_state
          end_state = @diagram.end_states.first
          return end_state.id if end_state

          end_id = generate_state_id('end')
          state = Diagram::StateNode.new.tap do |s|
            s.id = end_id
            s.label = START_END_MARKER
            s.state_type = 'end'
          end
          @diagram.states << state
          end_id
        end

        def ensure_state_exists(state_id)
          return if @diagram.find_state(state_id)

          state = Diagram::StateNode.new.tap do |s|
            s.id = state_id
            s.label = state_id
            s.state_type = 'normal'
          end
          @diagram.states << state
        end

        def add_special_state(state_id, state_type)
          state = Diagram::StateNode.new.tap do |s|
            s.id = state_id
            s.label = state_id
            s.state_type = state_type
          end
          @diagram.states << state
        end

        def add_or_update_state(state_id, label, description = nil)
          existing = @diagram.find_state(state_id)
          if existing
            existing.label = label unless label.to_s.empty?
            existing.description = description if description
            existing
          else
            state = Diagram::StateNode.new.tap do |s|
              s.id = state_id
              s.label = label
              s.state_type = 'normal'
              s.description = description
            end
            @diagram.states << state
            state
          end
        end

        def create_transition(from_id, to_id, trigger = nil, guard = nil)
          # Ensure both states exist
          ensure_state_exists(from_id) unless from_id.start_with?('start_', 'end_')
          ensure_state_exists(to_id) unless to_id.start_with?('start_', 'end_')

          transition = Diagram::StateTransition.new.tap do |t|
            t.from_id = from_id
            t.to_id = to_id
            t.trigger = trigger
            t.guard_condition = guard
          end
          @diagram.transitions << transition
        end

        def parse_transition_label(label_data)
          return [nil, nil] unless label_data

          label_text = extract_text(label_data[:label_text] || label_data).strip
          return [nil, nil] if label_text.empty?

          # Parse trigger and guard from label
          # Format: "trigger [guard]" or just "trigger"
          if label_text =~ /^(.+?)\s*\[(.+?)\]\s*$/
            trigger = Regexp.last_match(1).strip
            guard = Regexp.last_match(2).strip
            [trigger, guard]
          else
            [label_text, nil]
          end
        end

        def generate_state_id(prefix)
          @state_counter += 1
          "#{prefix}_#{@state_counter}"
        end

        def extract_text(value)
          case value
          when Hash
            if value[:string]
              value[:string].to_s
            elsif value[:marker_type]
              value[:marker_type].to_s
            elsif value[:dir_value]
              value[:dir_value].to_s
            elsif value[:label_text]
              value[:label_text].to_s
            else
              value.values.first.to_s
            end
          when String
            value
          else
            value.to_s
          end
        end
      end
    end
  end
end