# frozen_string_literal: true

# Sirena output size over the mmdc reference size for the same input. Measured
# ratios for the committed fixtures run 0.026 (state_diagram) to 1.49
# (xy_chart), so the floor sits just under the smallest of them: output 50x
# smaller than the reference (ratio 0.02) is out of band.
module FixtureLengthBand
  FLOOR = 0.025
  CEILING = 2.0

  def self.cover?(ratio)
    ratio.between?(FLOOR, CEILING)
  end
end
