# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # A `== text ==` line across the whole diagram.
        class Divider
          attr_reader :label

          def initialize(label:)
            @label = label
            freeze
          end
        end
      end
    end
  end
end
