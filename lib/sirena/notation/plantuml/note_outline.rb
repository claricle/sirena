# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      # The path of a note's outline: a rectangle whose top right corner is
      # folded and whose pointer, the box's first separator, grows a tail
      # from the edge it ends on.
      module NoteOutline
        FOLD = 10.0
        TAIL_HALF = 4.0
        private_constant :FOLD, :TAIL_HALF

        module_function

        # @param box [Scene::Box] a note box
        # @return [String] an SVG path
        def call(box)
          points = edges(box, box.separators.first).flatten(1)
          commands = points.each_with_index.map do |(x, y), index|
            "#{index.zero? ? 'M' : 'L'} #{format('%g', x)} #{format('%g', y)}"
          end
          [*commands, "Z"].join(" ")
        end

        def edges(box, pointer)
          left = box.x
          top = box.y
          right = left + box.width
          bottom = top + box.height
          [[[left, top]],
           tail(pointer, :top, top, [left, right]),
           [[right - FOLD, top], [right, top + FOLD]],
           tail(pointer, :right, right, [top + FOLD, bottom]),
           [[right, bottom]],
           tail(pointer, :bottom, bottom, [right, left]),
           [[left, bottom]],
           tail(pointer, :left, left, [bottom, top])]
        end

        # The three points of a tail on one edge, in drawing order.
        def tail(pointer, side, edge, (from, to))
          return [] unless pointer && on_edge?(pointer, side, edge)

          half = to > from ? TAIL_HALF : -TAIL_HALF
          tail_points(pointer, side, edge, half)
        end

        def tail_points(pointer, side, edge, half)
          along = flat?(side) ? pointer.x2 : pointer.y2
          first, last = [along - half, along + half].map do |value|
            flat?(side) ? [value, edge] : [edge, value]
          end
          [first, [pointer.x1, pointer.y1], last]
        end

        def on_edge?(pointer, side, edge)
          value = flat?(side) ? pointer.y2 : pointer.x2
          (value - edge).abs < 0.001
        end

        def flat?(side)
          %i[top bottom].include?(side)
        end
      end
    end
  end
end
