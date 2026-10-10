# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # `ref over A, B: text`: a frame over the participants it names.
        class Ref
          attr_reader :targets, :label

          def initialize(targets:, label:)
            @targets = targets.freeze
            @label = label
            freeze
          end

          def parallel?
            false
          end
        end
      end
    end
  end
end
