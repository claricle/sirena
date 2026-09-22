# frozen_string_literal: true

# Sirena's SVG is a fraction of the mermaid reference's size, and the fraction
# differs per diagram type (the state_diagram reference is 358 KB of embedded
# styling). The band is therefore centred on each type's measured ratio, not
# on one global range wide enough for every type.
#
# A global FLOOR/CEILING band also ships (module method `.cover?`) for specs
# that only need to reject an obviously collapsed or inflated output without
# a per-type baseline. Measured ratios for the committed fixtures run 0.026
# (state_diagram) to 1.49 (xy_chart), so the floor sits just under the
# smallest of them.
module FixtureLengthBand
  FLOOR = 0.025
  CEILING = 2.0

  # Output may shrink or grow by this factor from the measured ratio. 2x
  # tolerates ordinary renderer changes; a 50x collapse is far outside it.
  FACTOR = 2.0

  def self.cover?(ratio)
    ratio.between?(FLOOR, CEILING)
  end

  def length_ratio(actual_svg, expected_svg)
    actual_svg.length.to_f / expected_svg.length
  end

  def within_length_band?(actual_svg, expected_svg, baseline)
    length_ratio(actual_svg, expected_svg).between?(baseline / FACTOR, baseline * FACTOR)
  end
end
