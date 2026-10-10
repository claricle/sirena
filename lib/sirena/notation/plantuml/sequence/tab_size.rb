# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # How far a fragment's keyword tab grows when `groupHeader` sets a
        # `FontSize` other than the diagram's text size. The two rates are
        # fitted to PlantUML 1.2026.6 at sizes 10, 20 and 30.
        class TabSize
          HEIGHT_PER_PX = 1.18
          BASELINE_PER_PX = 0.97

          attr_reader :size

          # @param size [Numeric, nil] the `FontSize`; nil keeps `base`
          # @param base [Numeric] the diagram's text size
          def initialize(size, base)
            @base = base.to_f
            @size = (size || base).to_f
          end

          def custom?
            size != @base
          end

          def scale
            size / @base
          end

          def height_growth
            ((size - @base) * HEIGHT_PER_PX).round(2)
          end

          def baseline_growth
            ((size - @base) * BASELINE_PER_PX).round(2)
          end
        end
      end
    end
  end
end
