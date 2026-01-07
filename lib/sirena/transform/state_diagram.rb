# frozen_string_literal: true

require_relative 'base'
require_relative '../diagram/state_diagram'

module Sirena
  module Transform
    # State diagram transformer for converting state diagram models to graphs.
    #
    # Converts a typed state diagram model into a generic graph structure
    # suitable for layout computation by elkrb. Handles state node dimension
    # calculation, transition mapping, and layout configuration.
    #
    # @example Transform a state diagram
    #   transform = StateDiagramTransform.new
    #   graph = transform.to_graph(state_diagram)
    class StateDiagramTransform < Base
      # Default font size for text measurement
      DEFAULT_FONT_SIZE = 14

      # Converts a state diagram to a graph structure.
      #
      # @param diagram [Diagram::StateDiagram] the state diagram to transform
      # @return [Hash] elkrb-compatible graph hash
      # @raise [TransformError] if diagram is invalid
      def to_graph(diagram)
        raise TransformError, 'Invalid diagram' unless diagram.valid?

        {
          id: diagram.id || 'state_diagram',
          children: transform_states(diagram),
          edges: transform_transitions(diagram),
          layoutOptions: layout_options(diagram)
        }
      end

      private

      def transform_states(diagram)
        diagram.states.map do |state|
          dims = calculate_state_dimensions(state)

          {
            id: state.id,
            width: dims[:width],
            height: dims[:height],
            labels: state_labels(state, dims),
            metadata: {
              state_type: state.state_type,
              description: state.description
            }
          }
        end
      end

      def transform_transitions(diagram)
        return [] if diagram.transitions.nil? || diagram.transitions.empty?

        diagram.transitions.map do |transition|
          {
            id: "#{transition.from_id}_to_#{transition.to_id}",
            sources: [transition.from_id],
            targets: [transition.to_id],
            labels: transition_labels(transition),
            metadata: {
              trigger: transition.trigger,
              guard_condition: transition.guard_condition
            }
          }
        end
      end

      def state_labels(state, dims)
        labels = []

        # Add state label
        if state.label && !state.label.empty?
          labels << {
            text: state.label,
            width: dims[:label_width],
            height: dims[:label_height]
          }
        end

        # Add description if present
        if state.description && !state.description.empty?
          desc_dims = measure_text(
            state.description,
            font_size: DEFAULT_FONT_SIZE - 2
          )
          labels << {
            text: state.description,
            width: desc_dims[:width],
            height: desc_dims[:height]
          }
        end

        labels
      end

      def transition_labels(transition)
        label = transition.label
        return [] if label.nil? || label.empty?

        label_dims = measure_text(label, font_size: DEFAULT_FONT_SIZE)

        [
          {
            text: label,
            width: label_dims[:width],
            height: label_dims[:height]
          }
        ]
      end

      def calculate_state_dimensions(state)
        label_text = state.label || state.id
        label_dims = measure_text(
          label_text,
          font_size: DEFAULT_FONT_SIZE
        )

        # Adjust dimensions based on state type
        state_dims = case state.state_type
                     when 'start', 'end'
                       calculate_terminal_dimensions
                     when 'choice'
                       calculate_choice_dimensions(label_dims)
                     when 'fork', 'join'
                       calculate_fork_join_dimensions
                     else
                       calculate_normal_state_dimensions(
                         label_dims,
                         state.description
                       )
                     end

        {
          width: state_dims[:width],
          height: state_dims[:height],
          label_width: label_dims[:width],
          label_height: label_dims[:height]
        }
      end

      def calculate_terminal_dimensions
        # Start and end states are small circles
        {
          width: 30,
          height: 30
        }
      end

      def calculate_choice_dimensions(label_dims)
        # Choice states are diamonds
        size = [label_dims[:width], label_dims[:height]].max + 40
        {
          width: size,
          height: size
        }
      end

      def calculate_fork_join_dimensions
        # Fork and join are represented as thick bars
        {
          width: 100,
          height: 10
        }
      end

      def calculate_normal_state_dimensions(label_dims, description)
        # Normal states are rounded rectangles
        width = label_dims[:width] + 40
        height = label_dims[:height] + 30

        # Add extra height if there's a description
        if description && !description.empty?
          desc_dims = measure_text(
            description,
            font_size: DEFAULT_FONT_SIZE - 2
          )
          height += desc_dims[:height] + 10
          width = [width, desc_dims[:width] + 40].max
        end

        # Minimum dimensions
        width = [width, 100].max
        height = [height, 50].max

        {
          width: width,
          height: height
        }
      end

      def layout_options(diagram)
        # State diagrams use layered algorithm for state machine flow
        # This ensures proper hierarchical layout of states with clear
        # transition paths from start to end states
        build_elk_options(
          algorithm: ALGORITHM_LAYERED,
          direction: direction_to_layout(diagram.direction),
          ElkOptions::NODE_NODE_SPACING => 60,
          ElkOptions::LAYER_SPACING => 60,
          ElkOptions::EDGE_NODE_SPACING => 40,
          ElkOptions::EDGE_EDGE_SPACING => 30,
          # SIMPLE node placement for predictable state flow
          ElkOptions::NODE_PLACEMENT => 'SIMPLE'
        )
      end

      def direction_to_layout(direction)
        case direction
        when 'TD', 'TB'
          DIRECTION_DOWN
        when 'LR'
          DIRECTION_RIGHT
        when 'RL'
          DIRECTION_LEFT
        when 'BT'
          DIRECTION_UP
        else
          DIRECTION_DOWN # Default direction
        end
      end
    end
  end
end
