# frozen_string_literal: true

module Sirena
  class TextMeasurement
    # Trebuchet MS kern adjustments used by the remaining Mindmap corpus.
    # Values are design units from the regular face's kern table.
    module TrebuchetKerning
      UNITS_PER_EM = 2048.0
      PAIRS = {
        " A" => -113,
        " T" => -37,
        "Pe" => -96,
        "Po" => -96,
        "Re" => -83,
        "Ro" => -83,
        "To" => -255,
      }.freeze

      module_function

      def adjustment(text, font_size:)
        units = text.each_char.each_cons(2).sum do |pair|
          PAIRS.fetch(pair.join, 0)
        end
        units * font_size / UNITS_PER_EM
      end
    end
  end
end
