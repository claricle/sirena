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
            labels: state_labels(state),
            metadata: {
              state_type: state.state_type,
              shape_type: state_shape_type(state),
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

      def state_labels(state)
        state_texts(state).each_with_index.map do |text, index|
          text_dims = measure_text(
            text,
            font_size: index.zero? ? DEFAULT_FONT_SIZE : DEFAULT_FONT_SIZE - 2
          )
          {
            text: text,
            width: text_dims[:width],
            height: text_dims[:height]
          }
        end
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
        texts = state_texts(state)
        label_text = texts.first || state.id
        label_dims = measure_text(
          label_text,
          font_size: DEFAULT_FONT_SIZE
        )

        # Adjust dimensions based on state type
        state_dims = case state_shape_type(state)
                     when 'start', 'end'
                       calculate_terminal_dimensions
                     when 'choice'
                       calculate_choice_dimensions(label_dims)
                     when 'fork', 'join'
                       calculate_fork_join_dimensions
                     else
                       calculate_normal_state_dimensions(
                         label_dims,
                         texts.drop(1)
                       )
                     end

        {
          width: state_dims[:width],
          height: state_dims[:height],
          label_width: label_dims[:width],
          label_height: label_dims[:height]
        }
      end

      # Parsed aliases and descriptions are Mermaid's ordered display text.
      # StateNode's scalar fields remain the fallback for callers that build
      # the model directly.
      def state_texts(state)
        descriptions = Array(state.descriptions).reject(&:empty?)
        return descriptions unless descriptions.empty?

        [state.label, state.description].compact.reject(&:empty?)
      end

      # Mermaid keeps the declared marker type, but displays a marker carrying
      # ANY display text as an ordinary rectangular state. An alias lands in
      # `descriptions`, never in the scalar `description`, so asking the scalar
      # alone left `state C <<choice>>` + `state "Label" as C` drawing a
      # polygon where mmdc 11.12.0 draws two rects, in both declaration orders.
      #
      # "Display text" here means `descriptions` or the scalar `description`,
      # and deliberately NOT the label. A label cannot be used: terminals carry
      # `label: "[*]"` with no descriptions, so keying the shape on the label
      # turns `[*]` into an ordinary state and its 30px circle into a 100px box.
      # Measured — adding a label check reddened "handles start state
      # dimensions", which is the guard that caught it.
      #
      # Nothing is lost by that. No parsed source produces a marker carrying a
      # label but no descriptions: `add_special_state` clears the label, and the
      # one input that sets one — `state C <<choice>>` with `state "L" as C` —
      # fills `descriptions` too, which the first check already catches. Only a
      # directly built model can hold that combination, and it keeps its
      # declared marker type.
      def state_shape_type(state)
        return 'normal' unless Array(state.descriptions).reject(&:empty?).empty?
        return 'normal' if state.description && !state.description.empty?

        state.state_type
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

      def calculate_normal_state_dimensions(label_dims, descriptions)
        # Normal states are rounded rectangles
        width = label_dims[:width] + 40
        height = label_dims[:height] + 30

        descriptions.each do |description|
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
