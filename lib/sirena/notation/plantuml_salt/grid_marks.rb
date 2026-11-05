# frozen_string_literal: true

require_relative "box"
require_relative "mark"

module Sirena
  module Notation
    module PlantUMLSalt
      # The rules PlantUML draws for a non-tree block: `+` a frame, `-` a
      # rule above, between and below the rows, `!` a rule left of, between
      # and right of the columns, `#` both. A rule between two cells runs
      # through the middle of the gap, an outer one along the block's edge.
      module GridMarks
        CELL_GAP = 2.0
        BLOCK_PAD = 1.0

        private

        def grid_rules(block, area, lefts, tops)
          cut_frame(area, lefts, tops) if block.border?
          rules_across(area, tops) if block.row_rules?
          rules_down(area, lefts) if block.column_rules?
        end

        # The frame, cut at every cell boundary into a line a cell, as
        # PlantUML draws it.
        def cut_frame(frame, lefts, tops)
          cut_across(frame, rule_lines(lefts, frame.left, frame.right))
          cut_down(frame, rule_lines(tops, frame.top, frame.bottom))
        end

        def cut_across(frame, bounds)
          bounds.each_cons(2) do |from, to|
            [frame.top, frame.bottom].each do |y|
              @marks << rule(from, y, to - from, 0.0)
            end
          end
        end

        def cut_down(frame, bounds)
          bounds.each_cons(2) do |from, to|
            [frame.left, frame.right].each do |x|
              @marks << rule(x, from, 0.0, to - from)
            end
          end
        end

        def rules_across(area, tops)
          rule_lines(tops, area.top, area.bottom).each do |y|
            @marks << rule(area.left, y, area.width, 0.0)
          end
        end

        def rules_down(area, lefts)
          rule_lines(lefts, area.left, area.right).each do |x|
            @marks << rule(x, area.top, 0.0, area.height)
          end
        end

        def rule_lines(starts, first, last)
          [first, *starts.drop(1).map { |start| start - (CELL_GAP / 2) }, last]
        end
      end
    end
  end
end
