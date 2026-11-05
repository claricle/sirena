# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUMLSalt
      # The vertical metrics of the face PlantUML sets salt text in: DejaVu
      # Sans, the platform sans-serif on Linux, where PlantUML is normally
      # run. Java sizes a line from the font's hhea table, ascent + descent
      # + line gap, scaled to the font size; DejaVu Sans 2.37 carries
      # 1901, 483 and 0 units on a 2048-unit em. Every vertical constant
      # in the salt layout is built from these two numbers, so the layout
      # holds one place that knows the face.
      module FontMetrics
        UNITS_PER_EM = 2048.0
        ASCENT_UNITS = 1901
        DESCENT_UNITS = 483
        LINE_GAP_UNITS = 0
        SIZE = 12

        # Where a size-12 baseline sits below the top of its line.
        ASCENT = ASCENT_UNITS * SIZE / UNITS_PER_EM
        # How tall a size-12 line is.
        LINE_UNITS = ASCENT_UNITS + DESCENT_UNITS + LINE_GAP_UNITS
        HEIGHT = LINE_UNITS * SIZE / UNITS_PER_EM
      end
    end
  end
end
