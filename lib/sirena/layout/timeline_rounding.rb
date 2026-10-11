# frozen_string_literal: true

module Sirena
  module Layout
    # Rounds published timeline coordinates so sums such as 100.6 + 11
    # never leave float noise in the scene.
    module TimelineRounding
      # Decimal places of every published timeline coordinate.
      PLACES = 4

      module_function

      # @return [Float] the value without accumulated float noise
      def tidy(value)
        value.to_f.round(PLACES)
      end
    end
  end
end
