# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Timing
        # Draws a message as an arrow from one track to another, with its
        # text beside it.
        class Arrows
          BLUE = "#00008B"
          HEAD = 7.5
          WING = 2.74
          STROKE = "1.5"
          LABEL_SIZE = 14
          LABEL_DROP = 15.5
          private_constant :BLUE, :HEAD, :WING, :STROKE, :LABEL_SIZE,
                           :LABEL_DROP

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
            @pen.line(*tail, *tip, stroke: BLUE, stroke_width: STROKE)
            head(tail, tip)
            label(message.text, tail, tip)
          end

          private

          def point(id, time)
            [@axis.x(time), @lookup.call(id, time)]
          end

          # PlantUML sets the message in serif, just under the arrow's tip.
          def label(text, _tail, tip)
            @pen.text(text, tip[0], tip[1] + LABEL_DROP, fill: BLUE,
                                                         family: "Serif",
                                                         size: LABEL_SIZE)
          end

          def head(tail, tip)
            return if tail == tip

            dir = unit(tail, tip)
            base = [tip[0] - (HEAD * dir[0]), tip[1] - (HEAD * dir[1])]
            @pen.polygon([tip, wing(base, dir, WING), wing(base, dir, -WING)],
                         fill: BLUE, stroke: BLUE, stroke_width: STROKE)
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
