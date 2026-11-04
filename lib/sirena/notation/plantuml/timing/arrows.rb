# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Timing
        # Draws a message as an arrow from one track to another, with its
        # text beside it.
        class Arrows
          BLUE = "#00008B"
          HEAD = 8.0
          WING = 3.0
          private_constant :BLUE, :HEAD, :WING

          # @param pen [Drawing::Pen]
          # @param axis [Axis]
          # @param lookup [#call] `(participant id, time)` to the [x, y] of
          #   that participant's signal at that time
          def initialize(pen, axis, lookup)
            @pen = pen
            @axis = axis
            @lookup = lookup
          end

          def draw(message)
            tail = point(message.from, message.time)
            tip = point(message.to, message.arrives || message.time)
            @pen.line(*tail, *tip, stroke: BLUE)
            head(tail, tip)
            label(message.text, tail, tip)
          end

          private

          def point(id, time)
            [@axis.x(time), @lookup.call(id, time)]
          end

          def label(text, tail, tip)
            @pen.text(text, ((tail[0] + tip[0]) / 2) + 4,
                      (tail[1] + tip[1]) / 2, fill: BLUE)
          end

          def head(tail, tip)
            return if tail == tip

            dir = unit(tail, tip)
            base = [tip[0] - (HEAD * dir[0]), tip[1] - (HEAD * dir[1])]
            @pen.polygon([tip, wing(base, dir, WING), wing(base, dir, -WING)],
                         fill: BLUE, stroke: BLUE)
          end

          def unit(tail, tip)
            delta = tip.zip(tail).map { |to, from| to - from }
            length = Math.hypot(*delta)
            delta.map { |part| part / length }
          end

          # A point `side` away from `base`, across the arrow.
          def wing(base, dir, side)
            [base[0] - (side * dir[1]), base[1] + (side * dir[0])]
          end
        end
      end
    end
  end
end
