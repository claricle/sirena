# frozen_string_literal: true

require_relative "arrow_head"

module Sirena
  module Notation
    module PlantUML
      module Activity
        # Draws an edge: its path, its arrow head and its label.
        class EdgeMarks
          INK = "#181818"
          DASHES = { dashed: "7,5", dotted: "2,4" }.freeze
          private_constant :INK, :DASHES

          def initialize(router, canvas)
            @router = router
            @canvas = canvas
          end

          # @param edge [Edge]
          def draw(edge)
            return if edge.from.equal?(edge.to)

            route = @router.call(edge)
            paint(edge, route.points)
            label(edge, route)
          end

          private

          def paint(edge, points)
            colour = edge.colour || INK
            @canvas.path(points, stroke: colour, width: width(edge),
                                 dash: DASHES[edge.style])
            @canvas.polygon(ArrowHead.points(points.last(2)), fill: colour,
                                                              stroke: colour)
          end

          def width(edge)
            edge.style == :bold ? 2.5 : 1.0
          end

          def label(edge, route)
            return unless edge.label

            @canvas.lines(edge.label.split("\n"),
                          [route.label_x, route.label_y],
                          anchor: route.anchor)
          end
        end
      end
    end
  end
end
