# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # One edge of a `alt ... else ... end` style block. `phase` is :open,
        # :else or :close; `keyword` is the opening word (alt, loop, group).
        # An :open edge is `parallel` when its line began with `&`.
        class Fragment
          attr_reader :phase, :keyword, :label

          def initialize(phase:, keyword:, label: nil, parallel: false)
            @phase = phase
            @keyword = keyword
            @label = label
            @parallel = parallel
            freeze
          end

          def parallel?
            @parallel
          end
        end
      end
    end
  end
end
