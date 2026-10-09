# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # `destroy X`, or the `!!` that ends a message line: a cross on the
        # lifeline of `participant`.
        class Destroy
          attr_reader :participant

          def initialize(participant:)
            @participant = participant
            freeze
          end
        end
      end
    end
  end
end
