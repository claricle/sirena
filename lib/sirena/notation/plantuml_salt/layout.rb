# frozen_string_literal: true

require_relative "../../text_measurement"
require_relative "box"
require_relative "mark"
require_relative "run"
require_relative "scene"
require_relative "tree_marks"

module Sirena
  module Notation
    module PlantUMLSalt
      # Measures a {Block} tree and places it. Rows are as tall as their
      # tallest cell; every column is as wide as its widest cell. A tree
      # row's first cell is pushed right by its depth.
      class Layout
        include TreeMarks

        TREE_ROW_HEIGHT = TreeMarks::ROW_HEIGHT
        TREE_PAD = TreeMarks::PAD
        TREE_INDENT = TreeMarks::INDENT
        TREE_TEXT_DROP = TreeMarks::TEXT_DROP

        FONT_SIZE = 12
        ROW_HEIGHT = 24.0
        CELL_PAD = 8.0
        MARGIN = 6.0
        BOX = 12.0
        BOLD_FACTOR = 1.07
        FIELD_MIN = 60.0
        WIDGET_HEIGHT = 18.0
        CANVAS_RIGHT = 4.0
        CANVAS_BOTTOM = 6.4

        # @param block [Block] the parsed root
        # @return [Scene]
        def call(block, **)
          @marks = []
          width, height = measure(block)
          place(block, Box.new(MARGIN, MARGIN, width, height))
          Scene.new(width: (width + MARGIN + CANVAS_RIGHT).ceil,
                    height: (height + MARGIN + CANVAS_BOTTOM).ceil,
                    marks: @marks)
        end

        private

        def measure(block)
          [column_widths(block).sum,
           block.rows.sum { |row| row_height(block, row) }]
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

        # The space before and after a cell's content. A tree row's first
        # cell is pushed right by its depth; a nested block that draws no
        # frame of its own sits flush against its container.
        def edges(cell, block, row, index)
          return [0.0, 0.0] if cell.is_a?(Block) && cell.flush?
          return [CELL_PAD, CELL_PAD] unless block.tree?

          [tree_lead(row, index), TREE_PAD]
        end

        def tree_lead(row, index)
          return TREE_PAD unless index.zero? && row.depth.positive?

          row.depth * TREE_INDENT
        end

        def row_height(block, row)
          floor = block.tree? ? TREE_ROW_HEIGHT : ROW_HEIGHT
          row.cells.map { |cell| cell_height(cell, floor) }.max.to_f
        end

        def cell_height(cell, floor)
          return floor unless cell.is_a?(Block)

          [measure(cell)[1] + (cell.flush? ? 0.0 : CELL_PAD), floor].max
        end

        def cell_width(cell, block, row, index)
          width = cell.is_a?(Block) ? measure(cell)[0] : widget_width(cell)
          edges(cell, block, row, index).sum + width
        end

        def widget_width(widget)
          label = runs_width(widget.runs)
          case widget.kind
          when :empty then 0.0
          when :button then label + 16
          when :field then [label + 16, FIELD_MIN].max
          when :droplist then label + 32
          when :checkbox, :radio then BOX + 6 + label
          else label
          end
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
          place_rows(block, columns, area)
          chrome(block, columns, area)
          tree_decor(block, columns, area) if block.tree?
        end

        def place_rows(block, columns, area)
          top = area.top
          block.rows.each do |row|
            band = Box.new(area.left, top, area.width, row_height(block, row))
            place_row(block, row, columns, band)
            row_rule(block, band) unless row.equal?(block.rows.last)
            top = band.bottom
          end
        end

        def place_row(block, row, columns, band)
          left = band.left
          row.cells.each_with_index do |cell, index|
            lead = edges(cell, block, row, index).first
            place_cell(cell, left + lead, band, block)
            left += columns[index]
          end
        end

        def place_cell(cell, left, band, block)
          if cell.is_a?(Block)
            width, height = measure(cell)
            drop = cell.flush? ? 0.0 : CELL_PAD / 2
            place(cell, Box.new(left, band.top + drop, width, height))
          else
            draw_widget(cell, left, band.top + middle_of(block, band))
          end
        end

        def middle_of(block, band)
          block.tree? ? TREE_TEXT_DROP : band.height / 2
        end

        def draw_widget(widget, left, middle)
          case widget.kind
          when :empty then nil
          when :checkbox, :radio then ticked(widget, left, middle)
          when :text then text(widget.runs, left, middle)
          else boxed(widget, left, middle)
          end
        end

        def boxed(widget, left, middle)
          width = widget_width(widget)
          outline(widget.kind.to_s, left, middle, width)
          text(widget.runs, left + 8, middle)
          arrow(left + width - 16, middle) if widget.kind == :droplist
        end

        def outline(fill, left, middle, width)
          top = middle - (WIDGET_HEIGHT / 2)
          @marks << Mark.new(:rect, Box.new(left, top, width, WIDGET_HEIGHT),
                             fill: fill)
        end

        def arrow(left, middle)
          @marks << Mark.new(:text, Box.new(left, middle, 8.0, 0.0),
                             run: Run.new("v"))
        end

        def ticked(widget, left, middle)
          fill = "#{widget.kind}#{'-checked' if widget.checked}"
          @marks << Mark.new(:rect, Box.new(left, middle - (BOX / 2), BOX, BOX),
                             fill: fill)
          text(widget.runs, left + BOX + 6, middle)
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

        def row_rule(block, band)
          return if block.tree? || !(block.grid? || block.row_lines?)

          @marks << rule(band.left, band.bottom, band.width, 0.0)
        end

        def chrome(block, columns, area)
          return if block.tree?

          @marks << Mark.new(:rect, area, fill: "frame") if block.border?
          return unless block.grid? || block.column_lines?

          left = area.left
          columns[0...-1].each do |width|
            left += width
            @marks << rule(left, area.top, 0.0, area.height)
          end
        end
      end
    end
  end
end
