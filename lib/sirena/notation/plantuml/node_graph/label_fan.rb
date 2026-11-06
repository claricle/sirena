# frozen_string_literal: true

require_relative "../../../text_measurement"
require_relative "label_waypoint"

module Sirena
  module Notation
    module PlantUML
      module NodeGraph
        # The labels of links that would print over one another on the
        # middle of their lines: the JAR gives each its own place in the
        # rank between the ends and bends the link through it, so the labels
        # of a fan of links stand side by side.
        class LabelFan
          # The height of a label line.
          LINE = 14.0
          FONT_SIZE = 12

          # @param axis [Integer] 0 when ranks run left to right, else 1
          def initialize(axis)
            @axis = axis
          end

          # Bends the crowded links of `routes` through their label points,
          # in place.
          #
          # @param routes [Array<Route>]
          def call(routes)
            fan = routes.select { |route| labelled?(route) }
            fan.select { |route| crowded?(route, fan) }.each do |route|
              bend(route)
            end
          end

          private

          def labelled?(route)
            edge = route.edge
            !edge.label.to_s.empty? && route.points.size == 2 &&
              !(edge.pointer || edge.from_row || edge.to_row || edge.ends)
          end

          def crowded?(route, fan)
            fan.any? { |other| !other.equal?(route) && meet?(route, other) }
          end

          def meet?(first, second)
            across = distance(first, second, 1 - @axis)
            along = distance(first, second, @axis)
            along < LINE && across < (width(first) + width(second)) / 2
          end

          def distance(first, second, axis)
            (middle(first)[axis] - middle(second)[axis]).abs
          end

          def middle(route)
            route.points.transpose.map { |values| values.sum / 2 }
          end

          def width(route)
            Drawing::Face.width(route.edge.label, size: FONT_SIZE).to_f
          end

          def bend(route)
            anchor = LabelWaypoint.through(route.points, @axis)
            return unless anchor

            route.points = [route.points.first, anchor, route.points.last]
            route.label_at = anchor
          end
        end
      end
    end
  end
end
