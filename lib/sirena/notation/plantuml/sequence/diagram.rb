# frozen_string_literal: true

require_relative "message"

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # What the sequence parser returns: participants in order of first
        # mention, the items (messages, notes, fragment edges, dividers) in
        # source order and the boxes around neighbouring participants.
        # Private to this notation.
        class Diagram
          attr_reader :participants, :items, :boxes, :min_head_width

          # @param min_head_width [Integer, nil] the narrowest participant head
          #   the source asked for
          def initialize(participants:, items:, boxes: [].freeze,
                         min_head_width: nil)
            @participants = participants
            @items = items
            @boxes = boxes
            @min_head_width = min_head_width
            freeze
          end

          def messages
            items.grep(Message)
          end

          # The parser refuses a diagram with no participant.
          def valid?
            !participants.empty?
          end

          def diagram_type
            :sequence_diagram
          end
        end
      end
    end
  end
end
