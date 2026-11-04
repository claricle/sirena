# frozen_string_literal: true

require_relative "../../text_measurement"
require_relative "box"
require_relative "mark"
require_relative "run"
require_relative "scene"
require_relative "grid_marks"
require_relative "tree_marks"
require_relative "widget_marks"

module Sirena
  module Notation
    module PlantUMLSalt
      # Measures a {Block} tree and places it. Rows are as tall as their
      # tallest cell; every column is as wide as its widest cell. A tree
      # row's first cell is pushed right by its depth.
      class Layout
        include TreeMarks
        include GridMarks
        include WidgetMarks

        TREE_ROW_HEIGHT = TreeMarks::ROW_HEIGHT
        TREE_PAD = TreeMarks::PAD
        TREE_INDENT = TreeMarks::INDENT

        FONT_SIZE = 12
        MARGIN = 5.0
        BOLD_FACTOR = 1.07

        # @param block [Block] the parsed root
        # @return [Scene]
        def call(block, **)
          @marks = []
          root = block.rows.size == 1 ? lone_block(block) : block
          width, height = measure(root)
          place(root, Box.new(MARGIN, MARGIN, width, height))
          Scene.new(width: (width + (2 * MARGIN)).ceil,
                    height: (height + (2 * MARGIN)).ceil,
                    marks: @marks)
        end

        private

        def lone_block(block)
          cells = block.rows.first.cells
          cells.size == 1 && cells.first.is_a?(Block) ? cells.first : block
        end

        # The outer size of a block: its cells, the gaps between them and,
        # outside a tree, a pad on every side.
        def measure(block)
          columns = column_widths(block)
          heights = block.rows.map { |row| row_height(block, row) }
          return [columns.sum - TreeMarks::OVERHANG, heights.sum] if block.tree?

          [grid_extent(columns), grid_extent(heights)]
        end

        def grid_extent(sizes)
          sizes.sum + (CELL_GAP * [sizes.size - 1, 0].max) + (2 * BLOCK_PAD)
        end

        def column_widths(block)
          widths = []
          block.rows.each do |row|
            row.cells.each_with_index do |cell, index|
              wide = cell_width(cell, block, row, index)
              widths[index] = [widths[index].to_f, wide].max
            end
          end
          widths
        end

        # The space before and after a tree cell's content. A tree row's
        # first cell is pushed right by its depth; a nested block sits
        # flush against its container.
        def edges(cell, block, row, index)
          return [0.0, 0.0] if !block.tree? || cell.is_a?(Block)

          [tree_lead(row, index), TREE_PAD]
        end

        def tree_lead(row, index)
          return TREE_PAD unless index.zero? && row.depth.positive?

          row.depth * TREE_INDENT
        end

        def row_height(block, row)
          floor = block.tree? ? TREE_ROW_HEIGHT : 0.0
          row.cells.map { |cell| cell_height(cell, floor) }.max.to_f
        end

        def cell_height(cell, floor)
          height = cell.is_a?(Block) ? measure(cell)[1] : widget_height(cell)
          [height, floor].max
        end

        def cell_width(cell, block, row, index)
          width = cell.is_a?(Block) ? measure(cell)[0] : widget_width(cell)
          edges(cell, block, row, index).sum + width
        end

        def runs_width(runs)
          runs.sum { |run| run_width(run) }
        end

        def run_width(run)
          width = TextMeasurement.measure(run.text,
                                          font_size: FONT_SIZE)[:width]
          run.bold ? width * BOLD_FACTOR : width
        end

        def place(block, area)
          columns = column_widths(block)
          lefts, tops = slots(block, columns, area)
          place_rows(block, lefts, tops)
          return tree_decor(block, columns, area) if block.tree?

          grid_rules(block, area, lefts, tops)
        end

        # Where each column and each row starts.
        def slots(block, columns, area)
          pad = block.tree? ? 0.0 : BLOCK_PAD
          gap = block.tree? ? 0.0 : CELL_GAP
          heights = block.rows.map { |row| row_height(block, row) }
          [offsets(columns, area.left + pad, gap),
           offsets(heights, area.top + pad, gap)]
        end

        # The start of each size's slot when slots follow each other.
        def offsets(sizes, from, gap)
          sizes.each_with_object([from]) do |size, starts|
            starts << (starts.last + size + gap)
          end.first(sizes.size)
        end

        def place_rows(block, lefts, tops)
          block.rows.each_with_index do |row, line|
            row.cells.each_with_index do |cell, index|
              lead = edges(cell, block, row, index).first
              place_cell(cell, lefts[index] + lead, tops[line])
            end
          end
        end

        def place_cell(cell, left, top)
          return draw_widget(cell, left, top) unless cell.is_a?(Block)

          width, height = measure(cell)
          place(cell, Box.new(left, top, width, height))
        end

        def text(runs, left, middle)
          runs.each do |run|
            box = Box.new(left, middle, run_width(run), 0.0)
            @marks << Mark.new(:text, box, run: run)
            decorate(run, box)
            left = box.right
          end
        end

        def decorate(run, box)
          @marks << rule(box.left, box.top + 2, box.width, 0.0) if run.underline
          @marks << rule(box.left, box.top, box.width, 0.0) if run.strike
        end

        def rule(left, top, width, height)
          Mark.new(:line, Box.new(left, top, width, height))
        end
      end
    end
  end
end
