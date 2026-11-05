# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module State
        # Where {Routes} slides a transition's label along its chord, away
        # from container titles and from the state many transitions meet at.
        module LabelClearance
          CHORD_STEPS = 40
          CROWD = 4
          CROWD_SHIFT = 0.15
          private_constant :CHORD_STEPS, :CROWD, :CROWD_SHIFT

          private

          # @return [Hash{String=>Integer}] how many transitions meet at
          #   each state
          def degrees(edges)
            edges.each_with_object(Hash.new(0)) do |edge, found|
              ends = [edge[:sources].first, edge[:targets].first].uniq
              ends.each { |id| found[id] += 1 } if ends.size == 2
            end
          end

          # The route moved along its chord so its label sits where the
          # chord is outside the containers of both ends, not over a
          # container's title, and away from a crowded end.
          def clear_of_containers(edge, points)
            slide = clear_middle(edge, points) + crowd_bias(edge) - 0.5
            return points if slide.zero?

            along = chord(points).map { |run| run * slide }
            points.map { |point| point.zip(along).map(&:sum) }
          end

          def chord(points)
            points.last.zip(points.first).map { |to, from| to - from }
          end

          # @return [Float] the middle, as a fraction of the chord, of the
          #   stretch outside both ends' containers; 0.5 when there is none
          def clear_middle(edge, points)
            boxes = foreign_containers(edge)
            steps = (0..CHORD_STEPS).map { |step| step.fdiv(CHORD_STEPS) }
            clear = steps.select { |at| open?(boxes, points, at) }
            return 0.5 if boxes.empty? || clear.size < 2

            (clear.first + clear.last) / 2.0
          end

          def open?(boxes, points, at)
            spot = points.first.zip(chord(points)).map do |from, run|
              from + (run * at)
            end
            boxes.none? { |box| holds?(box, spot) }
          end

          # A label moves toward the far end of a chord that leaves or
          # reaches a state many transitions meet at.
          def crowd_bias(edge)
            out = @degree[edge[:sources].first]
            into = @degree[edge[:targets].first]
            return 0.0 if [out, into].max < CROWD

            out > into ? CROWD_SHIFT : -CROWD_SHIFT
          end

          # The boxes around only one end of the edge.
          def foreign_containers(edge)
            source = ancestors(edge[:sources].first)
            target = ancestors(edge[:targets].first)
            (source - target) + (target - source)
          end

          def ancestors(id)
            found = []
            while (owner = @parent[id])
              found << @boxes.fetch(owner)
              id = owner
            end
            found
          end

          def holds?(box, spot)
            spot.first.between?(box.x, box.x + box.w) &&
              spot.last.between?(box.y, box.y + box.h)
          end
        end
      end
    end
  end
end
