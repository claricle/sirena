# frozen_string_literal: true

require_relative "../../text_measurement"
require_relative "box"
require_relative "mark"
require_relative "run"
require_relative "scene"

module Sirena
  module Notation
    module PlantUMLSalt
      # Measures a {Block} tree and places it. Rows are as tall as their
      # tallest cell; every column is as wide as its widest cell. A tree
      # row's first cell is pushed right by its depth.
      class Layout
        FONT_SIZE = 12
        ROW_HEIGHT = 24.0
        CELL_PAD = 8.0
        INDENT = 16.0
        MARGIN = 10.0
        BOX = 12.0
        BOLD_FACTOR = 1.07
        FIELD_MIN = 60.0
        WIDGET_HEIGHT = 18.0

        # @param block [Block] the parsed root
        # @return [Scene]
        def call(block, **)
          @marks = []
          width, height = measure(block)
          canvas = window(width, height)
          place(block, Box.new(MARGIN, MARGIN, width, height))
          Scene.new(width: canvas.width + 1, height: canvas.height + 1,
                    marks: @marks)
        end

        private

        def window(width, height)
          canvas = Box.new(0.5, 0.5, width + (2 * MARGIN),
                           height + (2 * MARGIN))
          @marks << Mark.new(:rect, canvas, fill: "window")
          canvas
        end

        def measure(block)
          [column_widths(block).sum, block.rows.sum { |row| row_height(row) }]
        end

        def column_widths(block)
          widths = []
          block.rows.each do |row|
            row.cells.each_with_index do |cell, index|
              wide = cell_width(cell) + (index.zero? ? indent(block, row) : 0)
              widths[index] = [widths[index].to_f, wide].max
            end
          end
          widths
        end

        def indent(block, row)
          block.tree? ? [row.depth - 1, 0].max * INDENT : 0.0
        end

        def row_height(row)
          row.cells.map { |cell| cell_height(cell) }.max.to_f
        end

        def cell_height(cell)
          return ROW_HEIGHT unless cell.is_a?(Block)

          measure(cell)[1] + CELL_PAD
        end

        def cell_width(cell)
          width = cell.is_a?(Block) ? measure(cell)[0] : widget_width(cell)
          width + (2 * CELL_PAD)
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
        end

        def place_rows(block, columns, area)
          top = area.top
          block.rows.each do |row|
            band = Box.new(area.left, top, area.width, row_height(row))
            place_row(block, row, columns, band)
            row_rule(block, band) unless row.equal?(block.rows.last)
            top = band.bottom
          end
        end

        def place_row(block, row, columns, band)
          left = band.left
          row.cells.each_with_index do |cell, index|
            extra = index.zero? ? indent(block, row) : 0.0
            place_cell(cell, left + CELL_PAD + extra, band)
            left += columns[index]
          end
        end

        def place_cell(cell, left, band)
          if cell.is_a?(Block)
            width, height = measure(cell)
            place(cell, Box.new(left, band.top + (CELL_PAD / 2), width, height))
          else
            draw_widget(cell, left, band.top + (band.height / 2))
          end
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
          return unless block.grid? || block.row_lines?

          @marks << rule(band.left, band.bottom, band.width, 0.0)
        end

        def chrome(block, columns, area)
          if block.border?
            @marks << Mark.new(:rect, area, fill: "frame")
          end
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
