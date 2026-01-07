# frozen_string_literal: true

require_relative 'base'
require_relative '../diagram/sequence'

module Sirena
  module Transform
    # Sequence transformer for converting sequence models to graphs.
    #
    # Converts a typed sequence diagram model into a generic graph structure
    # suitable for layout computation by elkrb. Handles participant
    # positioning, message routing, and lifeline calculation.
    #
    # @example Transform a sequence diagram
    #   transform = SequenceTransform.new
    #   graph = transform.to_graph(sequence_diagram)
    class SequenceTransform < Base
      # Default font size for text measurement
      DEFAULT_FONT_SIZE = 14

      # Minimum spacing between participants
      PARTICIPANT_SPACING = 150

      # Width of participant box
      PARTICIPANT_WIDTH = 120

      # Height of participant box
      PARTICIPANT_HEIGHT = 40

      # Vertical spacing between messages
      MESSAGE_SPACING = 60

      # Converts a sequence diagram to a graph structure.
      #
      # @param diagram [Diagram::Sequence] the sequence diagram to transform
      # @return [Hash] elkrb-compatible graph hash
      # @raise [TransformError] if diagram is invalid
      def to_graph(diagram)
        raise TransformError, 'Invalid diagram' unless diagram.valid?

        {
          id: diagram.id || 'sequence',
          children: transform_participants(diagram),
          edges: transform_messages(diagram),
          layoutOptions: layout_options(diagram),
          metadata: {
            participants: diagram.participants.map(&:id),
            message_count: diagram.messages.length,
            notes: diagram.notes
          }
        }
      end

      private

      def transform_participants(diagram)
        diagram.participants.map.with_index do |participant, index|
          {
            id: participant.id,
            width: PARTICIPANT_WIDTH,
            height: PARTICIPANT_HEIGHT,
            labels: [
              {
                text: participant.label,
                width: measure_text(participant.label,
                                    font_size: DEFAULT_FONT_SIZE)[:width],
                height: measure_text(participant.label,
                                     font_size: DEFAULT_FONT_SIZE)[:height]
              }
            ],
            metadata: {
              actor_type: participant.actor_type,
              index: index,
              lifeline_length: calculate_lifeline_length(diagram)
            }
          }
        end
      end

      def transform_messages(diagram)
        return [] if diagram.messages.nil? || diagram.messages.empty?

        diagram.messages.map.with_index do |message, index|
          {
            id: "msg_#{index}",
            sources: [message.from_id],
            targets: [message.to_id],
            labels: message_labels(message),
            metadata: {
              arrow_type: message.arrow_type,
              message_index: index,
              message_text: message.message_text
            }
          }
        end
      end

      def message_labels(message)
        return [] if message.message_text.nil? || message.message_text.empty?

        label_dims = measure_text(
          message.message_text,
          font_size: DEFAULT_FONT_SIZE
        )

        [
          {
            text: message.message_text,
            width: label_dims[:width],
            height: label_dims[:height]
          }
        ]
      end

      def calculate_lifeline_length(diagram)
        # Calculate total height needed for all messages
        message_count = diagram.messages.length
        base_height = message_count * MESSAGE_SPACING

        # Add extra space for notes if present
        note_count = diagram.notes&.length || 0
        base_height + (note_count * 30)
      end

      def layout_options(_diagram)
        # Sequence diagrams use layered algorithm for vertical timeline
        # DIRECTION_DOWN ensures participants are arranged horizontally at top
        # with messages flowing downward in chronological order
        build_elk_options(
          algorithm: ALGORITHM_LAYERED,
          direction: DIRECTION_DOWN,
          ElkOptions::NODE_NODE_SPACING => PARTICIPANT_SPACING,
          ElkOptions::LAYER_SPACING => MESSAGE_SPACING,
          ElkOptions::EDGE_NODE_SPACING => 20,
          ElkOptions::EDGE_EDGE_SPACING => 15,
          # SIMPLE node placement maintains participant order
          ElkOptions::NODE_PLACEMENT => 'SIMPLE',
          ElkOptions::MODEL_ORDER => 'NODES_AND_EDGES'
        )
      end
    end
  end
end
