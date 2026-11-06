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
          QUESTION_GAP = 13.0
          private_constant :INK, :DASHES, :QUESTION_GAP

          # @param curved [Boolean] draw each straight edge as a cubic, as
          #   PlantUML does in the legacy syntax
          def initialize(router, canvas, curved: false)
            @router = router
            @canvas = canvas
            @curved = curved
          end

          # @param edge [Edge]
          def draw(edge)
            return if edge.from.equal?(edge.to)

            route = @router.call(edge)
            paint(edge, route.points)
            label(edge, route)
            question(edge.to, route.points.last(2)) if edge.to.bare
          end

          private

          def paint(edge, points)
            colour = edge.colour || INK
            @canvas.path(points, stroke: colour, width: width(edge),
                                 dash: DASHES[edge.style], curve: @curved)
            @canvas.polygon(ArrowHead.points(points.last(2)), fill: colour,
                                                              stroke: colour)
          end

          # A bare decision's question stands left of the arrow into it,
          # level with the middle of the arrow.
          def question(node, segment)
            tail, tip = segment
            @canvas.lines(node.lines, [tip.first - QUESTION_GAP,
                                       ((tail.last + tip.last) / 2) + 10.0],
                          anchor: "end", role: :arrow)
          end

          def width(edge)
            edge.style == :bold ? 2.5 : 1.0
          end

          def label(edge, route)
            return unless edge.label

            @canvas.lines(edge.label.split("\n"),
                          [route.label_x, route.label_y],
                          anchor: route.anchor, role: :arrow)
          end
        end
      end
    end
  end
end
