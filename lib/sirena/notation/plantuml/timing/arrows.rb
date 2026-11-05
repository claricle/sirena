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
          # Where the JAR sets a message's text from the tip: pulled back
          # along the arrow, then below the tip of a rising arrow and above
          # that of a falling one.
          PULL = 7.518
          BELOW = 7.98
          ABOVE = -8.11
          private_constant :BLUE, :HEAD, :WING, :STROKE, :LABEL_SIZE,
                           :PULL, :BELOW, :ABOVE

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
          def label(text, tail, tip)
            dir = tail == tip ? [0.0, -1.0] : unit(tail, tip)
            drop = dir.last.positive? ? ABOVE : BELOW
            @pen.text(text, tip[0] - (PULL * dir.first),
                      tip[1] + drop - (PULL * dir.last), fill: BLUE,
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
