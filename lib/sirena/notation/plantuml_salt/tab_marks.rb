# frozen_string_literal: true

require_relative "mark"
require_relative "widget"

module Sirena
  module Notation
    module PlantUMLSalt
      # The `{/` group: a row of tabs side by side, each open at the bottom
      # and joined to the next by a baseline rule.
      module TabMarks
        # A tab: its text sits two units in and the tab ends three units
        # past it; the baseline rule runs ten units on to the next tab.
        TAB_LEFT = 2.0
        TAB_PAD = 5.0
        TAB_RUN = 10.0

        private

        # A tab row's size: tabs side by side, each with its baseline rule.
        def tab_extent(block)
          widths = block.rows.map { |row| row.cells.sum { |c| tab_width(c) } }
          lines = block.rows.map { |row| tab_line(row) }
          [widths.max.to_f, stacked(lines)]
        end

        def stacked(lines)
          lines.sum + (GridMarks::CELL_GAP * [lines.size - 1, 0].max)
        end

        def tab_runs(cell)
          cell.is_a?(Widget) ? cell.runs : []
        end

        def tab_width(cell)
          runs_width(tab_runs(cell)) + TAB_PAD + TAB_RUN
        end

        def tab_line(row)
          line_of(row.cells.map { |cell| runs_size(tab_runs(cell)) }.max)
        end

        def place_tabs(block, area)
          top = area.top
          block.rows.each do |row|
            line = tab_line(row)
            row.cells.inject(area.left) do |left, cell|
              tab(tab_runs(cell), left, top, line)
            end
            top += line + GridMarks::CELL_GAP
          end
        end

        # A tab open at the bottom; the baseline rule runs on to the next
        # tab. Returns where that is.
        def tab(runs, left, top, line)
          width = runs_width(runs) + TAB_PAD
          text(runs, left + TAB_LEFT, top + runs_drop(runs))
          tab_outline(left, top, width, line)
          left + width + TAB_RUN
        end

        def tab_outline(left, top, width, line)
          [[left, top, 0.0, line],
           [left, top, width, 0.0],
           [left + width, top, 0.0, line],
           [left + width, top + line, TAB_RUN, 0.0]].each do |edge|
            @marks << rule(*edge)
          end
        end
      end
    end
  end
end
