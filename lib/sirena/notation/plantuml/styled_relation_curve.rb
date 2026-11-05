# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      # PlantUML routes a link written with a bracketed style such as
      # `-[#blue,thickness=8]->` as a spline, not a chord. Across one rank a
      # shallow link leaves its box flatter than the chord and arrives
      # steeper (measured on 1.2026.6: a link 468 wide and 95 deep starts at
      # about 0.8 of the chord slope and ends at about 1.75 of it). A steep
      # link stays on its chord.
      module StyledRelationCurve
        extend self

        SHALLOW_SLOPE = 0.5
        REACH = 0.4
        DEPARTURE = 0.3
        ARRIVAL = 0.6
        private_constant :SHALLOW_SLOPE, :REACH, :DEPARTURE, :ARRIVAL

        # @param relation [Relation]
        # @param from [Array(Float, Float)] the left end
        # @param to [Array(Float, Float)] the right end
        # @return [Array(Array, Array), nil] the two cubic control points, or
        #   nil when the link is not a styled, shallow one
        def controls(relation, from, to)
          return unless styled?(relation)

          run = to[0] - from[0]
          rise = to[1] - from[1]
          return unless shallow?(run, rise)

          [point(from, run, rise, REACH, DEPARTURE),
           point(to, -run, -rise, REACH, ARRIVAL)]
        end

        private

        def shallow?(run, rise)
          run.abs * SHALLOW_SLOPE > rise.abs && rise != 0
        end

        def point(origin, run, rise, reach, share)
          [origin[0] + (run * reach), origin[1] + (rise * share)]
        end

        def styled?(relation)
          relation.color || relation.width || relation.dotted?
        end
      end
    end
  end
end
