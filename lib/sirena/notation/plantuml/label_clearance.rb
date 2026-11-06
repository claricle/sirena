# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      # Where a link's label can sit without its own line running through the
      # text. The JAR keeps a label beside its line: above a flat one, to the
      # right of a steep one. A line that slopes under the label's width, or
      # across its height, reaches further than the middle the label is
      # centred on, so the label moves clear of the line's furthest point
      # under it.
      module LabelClearance
        extend self

        # @param from [Array(Float, Float)] one end of the line
        # @param to [Array(Float, Float)] the other end
        # @return [Float] the y of the line's highest point between the
        #   x values `left` and `right`
        def top_between(from, to, left, right)
          lowest = [from[1], to[1]].min
          [left, right].map { |x_pos| across(from, to, 0, x_pos, lowest) }.min
        end

        # @return [Float] the x of the line's rightmost point between the
        #   y values `top` and `bottom`
        def right_between(from, to, top, bottom)
          widest = [from[0], to[0]].max
          [top, bottom].map { |y_pos| across(from, to, 1, y_pos, widest) }.max
        end

        # @return [Float] the y of the line's lowest point between the x
        #   values `left` and `right`
        def bottom_between(from, to, left, right)
          highest = [from[1], to[1]].max
          [left, right].map { |x_pos| across(from, to, 0, x_pos, highest) }.max
        end

        # @return [Float] the x of the line's leftmost point between the y
        #   values `top` and `bottom`
        def left_between(from, to, top, bottom)
          narrowest = [from[0], to[0]].min
          [top, bottom].map do |y_pos|
            across(from, to, 1, y_pos, narrowest)
          end.min
        end

        private

        # The line's coordinate on the other axis where `axis` is `value`,
        # held to the ends of the line; `flat` when the line does not move
        # along `axis`.
        def across(from, to, axis, value, flat)
          share = share_of(from[axis], to[axis], value)
          return flat unless share

          other = 1 - axis
          from[other] + ((to[other] - from[other]) * share)
        end

        def share_of(start, stop, value)
          span = stop - start
          ((value - start) / span).clamp(0, 1) unless span.zero?
        end
      end
    end
  end
end
