# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # One edge of a `alt ... else ... end` style block. `phase` is :open,
        # :else or :close; `keyword` is the opening word (alt, loop, group).
        class Fragment
          attr_reader :phase, :keyword, :label

          def initialize(phase:, keyword:, label: nil)
            @phase = phase
            @keyword = keyword
            @label = label
            freeze
          end
        end
      end
    end
  end
end
