# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module NodeGraph
        # Bends a link around a box that its straight line would cross, as
        # the PlantUML JAR routes a spline past what is in the way.
        class Detour
          CLEARANCE = 14.0
          MAX_BENDS = 3
          # How far apart the points tested along a line are.
          STEP = 4.0
          EDGE_MARGIN = 4.0
          PORTS = %i[portin portout].freeze

          # @param placed [Array<Placed>] every placed node
          def initialize(placed)
            @placed = placed.reject do |box|
              PORTS.include?(box.node.kind)
            end
          end

          # @return [Array<Array(Float, Float)>] `points` with the bends
          #   needed to clear the boxes between its ends
          def call(edge, points)
            route = points.dup
            boxes = obstacles(edge)
            MAX_BENDS.times do
              index, box = blocked(route, boxes)
              break unless box

              route.insert(index + 1,
                           around(route[index], route[index + 1], box))
            end
            route
          end

          private

          # The boxes the link has no business with: not its ends, what
          # holds them, or what they hold.
          def obstacles(edge)
            @placed.reject do |box|
              chain = box.node.ancestors + [box.node]
              [edge.from, edge.to].any? do |node|
                (node.ancestors + [node]).include?(box.node) ||
                  chain.include?(node)
              end
            end
          end

          def blocked(route, boxes)
            route.each_cons(2).with_index do |(from, to), index|
              box = boxes.find { |candidate| crosses?(from, to, candidate) }
              return [index, box] if box
            end
            nil
          end

          def crosses?(from, to, box)
            steps = (Math.hypot(to[0] - from[0], to[1] - from[1]) / STEP).ceil
            (1...steps).any? do |step|
              inside?(box, *lerp(from, to, step.to_f / steps))
            end
          end

          def lerp(from, to, ratio)
            from.zip(to).map do |start, finish|
              start + ((finish - start) * ratio)
            end
          end

          def inside?(box, x_pos, y_pos)
            x_pos.between?(box.x, box.x + box.width) &&
              y_pos.between?(box.y, box.y + box.height)
          end

          # A point beside the box, on the side the line passes nearer.
          def around(from, to, box)
            middle = box.y + (box.height / 2)
            [nearer_side(box, crossing_x(from, to, middle)), middle]
          end

          def crossing_x(from, to, y_pos)
            rise = (to[1] - from[1]).nonzero? || 1e-9
            lerp(from, to, (y_pos - from[1]) / rise)[0]
          end

          def nearer_side(box, x_pos)
            [[box.x - CLEARANCE, EDGE_MARGIN].max,
             box.x + box.width + CLEARANCE].min_by { |side| (side - x_pos).abs }
          end
        end
      end
    end
  end
end
