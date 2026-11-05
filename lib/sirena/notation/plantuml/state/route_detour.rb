# frozen_string_literal: true

require_relative "plane"

module Sirena
  module Notation
    module PlantUML
      module State
        # Bends a transition around the states it would cross, as PlantUML's
        # splines do: waypoints beside each box in the way, by the side that
        # makes the shortest route, each route round a box in a lane of its
        # own.
        module RouteDetour
          CLEAR = 24.0
          LANE = 14.0
          GRAZE = 7.0
          PASSES = 6
          private_constant :CLEAR, :LANE, :GRAZE, :PASSES

          private

          # @return [Array<Array(Float, Float)>] the route with waypoints
          #   beside each box that blocks it
          def around_boxes(edge, points)
            rects = blockers_of(edge).map { |box| Plane.rect(box) }
            return points if rects.empty?

            PASSES.times.reduce(points) do |route, _|
              detoured = detour_once(route, rects)
              return detoured if detoured == route

              detoured
            end
          end

          # Boxes the edge neither starts in, ends in, nor runs inside of,
          # outermost only: going round a container clears what it holds.
          def blockers_of(edge)
            ends = [edge[:sources].first, edge[:targets].first]
            kin = ends.flat_map { |id| [id, *lineage(id)] }
            outside = @boxes.select do |id, box|
              outsider?(id, box, ends, kin)
            end
            outermost(outside).values
          end

          def outsider?(id, box, ends, kin)
            !kin.include?(id) && !note_box?(box) &&
              !lineage(id).intersect?(ends)
          end

          def outermost(boxes)
            boxes.reject { |id, _| lineage(id).any? { |up| boxes.key?(up) } }
          end

          def note_box?(box)
            box.node.dig(:metadata, :state_type) == "note"
          end

          def lineage(id)
            found = []
            found << id while (id = @parent[id])
            found
          end

          def detour_once(route, rects)
            route.each_cons(2).with_index do |(from, to), index|
              rect = nearest_crossed(rects, from, to)
              next unless rect

              return [*route[0..index], *waypoints(rect, from, to),
                      *route[(index + 1)..]]
            end
            route
          end

          def nearest_crossed(rects, from, to)
            rects.select { |rect| blocks?(rect, from, to) }.min_by do |rect|
              Plane.length([Plane.centre(rect), from])
            end
          end

          def blocks?(rect, from, to)
            Plane.crosses?(Plane.grow(rect, GRAZE), from, to)
          end

          # The way round the rect, a corner, or two corners of one side,
          # that is the shortest and leaves every stretch clear of it.
          def waypoints(rect, from, to)
            ways = ways_round(rect, lane_of(rect))
            clear = ways.select do |way|
              [from, *way, to].each_cons(2).none? do |a, b|
                blocks?(rect, a, b)
              end
            end
            (clear.empty? ? ways : clear).min_by do |way|
              Plane.length([from, *way, to])
            end
          end

          def lane_of(rect)
            @lanes[rect] += 1
            CLEAR + (LANE * (@lanes[rect] - 1))
          end

          def ways_round(rect, reach)
            corners = Plane.corners(Plane.grow(rect, reach))
            corners.zip + corners.each_cons(2).to_a +
              [[corners.last, corners.first]]
          end
        end
      end
    end
  end
end
