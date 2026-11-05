# frozen_string_literal: true

require_relative "box"
require_relative "mark"

module Sirena
  module Notation
    module PlantUMLSalt
      # The `{S` group's scroll bars: a strip beside the frame (or below
      # it) with a rule and an arrow at each end.
      module ScrollMarks
        # A scroll bar: a 15-wide strip four units from the frame, and
        # eleven units further that the group reserves beyond it.
        BAR_GAP = 4.0
        BAR_WIDTH = 15.0
        BAR_ROOM = BAR_GAP + BAR_WIDTH + 11.0
        BAR_END = 12.0
        # An arrow in a bar points at the bar's edge: its tip and its base
        # sit this far in from it, at the start of the bar and at its end,
        # and it is six across; the bar's centre line is 7 in.
        ARROW_START = [4.0, 9.0].freeze
        ARROW_END = [3.0, 8.0].freeze
        ARROW_HALF = 3.0
        BAR_AXIS = 7.0
        BAR_BLACK = "#000000"

        private

        def vertical_bar(frame)
          bar = Box.new(frame.right + BAR_GAP, frame.top, BAR_WIDTH,
                        frame.height)
          bar_body(bar, vertical_ends(bar))
          axis = bar.left + BAR_AXIS
          bar_arrows([axis, bar.top], [axis, bar.bottom], [0.0, 1.0])
        end

        def horizontal_bar(frame)
          bar = Box.new(frame.left, frame.bottom + BAR_GAP, frame.width,
                        BAR_WIDTH)
          bar_body(bar, horizontal_ends(bar))
          axis = bar.top + BAR_AXIS
          bar_arrows([bar.left, axis], [bar.right, axis], [1.0, 0.0])
        end

        def vertical_ends(bar)
          [bar.top + BAR_END, bar.bottom - BAR_END].map do |y|
            rule(bar.left, y, BAR_WIDTH, 0.0)
          end
        end

        def horizontal_ends(bar)
          [bar.left + BAR_END, bar.right - BAR_END].map do |x|
            rule(x, bar.top, 0.0, BAR_WIDTH)
          end
        end

        # The strip and the rules that close off its ends.
        def bar_body(bar, ends)
          @marks << Mark.new(:rect, bar, ink: BAR_BLACK)
          @marks.concat(ends)
        end

        # The arrows at the bar's start and end; `heading` is the unit step
        # from the start towards the end.
        def bar_arrows(start, finish, heading)
          bar_arrow(start, heading, ARROW_START)
          bar_arrow(finish, heading.map { |step| 0.0 - step }, ARROW_END)
        end

        # A triangle on the bar's `edge` point, pointing away from it along
        # `heading` (a unit step on one axis); `reach` is the tip's and the
        # base's distance from the edge.
        def bar_arrow(edge, heading, reach)
          @marks << Mark.new(:polygon, Box.new(*edge, 0.0, 0.0),
                             fill: BAR_BLACK, ink: BAR_BLACK,
                             points: arrow_points(edge, heading, reach))
        end

        def arrow_points(edge, heading, reach)
          dx, dy = heading
          tip, base = reach.map do |far|
            [edge[0] + (dx * far), edge[1] + (dy * far)]
          end
          sideways = [dy.abs * ARROW_HALF, dx.abs * ARROW_HALF]
          [tip, shift(base, sideways, 1), shift(base, sideways, -1)]
        end

        def shift(point, by, sign)
          [point[0] + (sign * by[0]), point[1] + (sign * by[1])]
        end
      end
    end
  end
end
