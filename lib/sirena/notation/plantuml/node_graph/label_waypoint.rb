# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module NodeGraph
        # The PlantUML JAR gives a link label a rank of its own between the
        # two ends and routes the spline through it, so the labels of a fan
        # of links sit side by side above their targets. This is the point
        # that spline passes through.
        module LabelWaypoint
          # How far toward the source from its target the label sits
          # (measured on 1.2026.6: a link 192 across carries its label 67
          # off its target, one 22 across 33).
          SHARE = 0.3
          # A label this close across to its target stays on the line.
          MIN_SPREAD = 12.0

          extend self

          # @param points [Array<Array(Float, Float)>] a link's points
          # @param axis [Integer] 0 when ranks run left to right, else 1
          # @return [Array(Float, Float), nil] the point, or nil when the
          #   link has bends of its own or runs straight
          def through(points, axis)
            return unless points.size == 2

            first, last = points
            spread = first[1 - axis] - last[1 - axis]
            return if spread.abs < MIN_SPREAD

            waypoint(first, last, axis, spread * SHARE)
          end

          private

          def waypoint(first, last, axis, share)
            [0.0, 0.0].tap do |point|
              point[axis] = (first[axis] + last[axis]) / 2
              point[1 - axis] = last[1 - axis] + share
            end
          end
        end
      end
    end
  end
end
