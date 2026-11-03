# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # A `...` or `... text ...` line: time passes between two messages.
        class Delay
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
