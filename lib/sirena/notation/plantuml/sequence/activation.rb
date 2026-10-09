# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # `activate X` or `deactivate X`, or the `++` and `--` that end a
        # message line: a bar on the lifeline of `participant` opens or
        # closes at this point.
        class Activation
          attr_reader :participant, :phase

          # @param phase [Symbol] :on or :off
          def initialize(participant:, phase:)
            @participant = participant
            @phase = phase
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
