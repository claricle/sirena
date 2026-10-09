# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # `activate X` or `deactivate X`, or the `++` and `--` that end a
        # message line: a bar on the lifeline of `participant` opens or
        # closes at this point. `color` is the fill of the bar it opens.
        class Activation
          attr_reader :participant, :phase, :color

          # @param phase [Symbol] :on or :off
          def initialize(participant:, phase:, color: nil)
            @participant = participant
            @phase = phase
            @color = color
            freeze
          end

          def on?
            phase == :on
          end
        end
      end
    end
  end
end
