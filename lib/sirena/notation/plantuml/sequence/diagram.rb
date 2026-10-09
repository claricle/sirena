# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # What the sequence parser returns: participants in order of first
        # mention, messages in source order and the boxes around neighbouring
        # participants. Private to this notation.
        class Diagram
          attr_reader :participants, :messages, :boxes

          def initialize(participants:, messages:, boxes: [].freeze)
            @participants = participants
            @messages = messages
            @boxes = boxes
            freeze
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
