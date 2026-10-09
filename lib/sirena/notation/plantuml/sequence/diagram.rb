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
          attr_reader :participants, :items, :boxes

          def initialize(participants:, items:, boxes: [].freeze)
            @participants = participants
            @items = items
            @boxes = boxes
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
