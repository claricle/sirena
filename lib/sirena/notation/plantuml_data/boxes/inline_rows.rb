# frozen_string_literal: true

require_relative "marks"
require_relative "text"

module Sirena
  module Notation
    module PlantUMLData
      module Boxes
        # Measures and draws the rows of a `json` element mixed into another
        # diagram. PlantUML draws such an element as one box: a nested object
        # or array fills the value cell of its row as rows of its own, and
        # an object keeps a key column of its own width.
        module InlineRows
          extend self

          ROW = 20.4883
          PAD = 5.0

          # @return [Float] the key column width plus the widest value cell
          def width(rows)
            key_width(rows) + (rows.map { |row| cell_width(row) }.max || 0.0)
          end

          # @return [Float] what the rows stack to
          def height(rows)
            rows.sum { |row| row.inline ? height(row.inline.rows) : ROW }
          end

          # @return [Float] the key column's width, 0 when no row is keyed
          def key_width(rows)
            return 0.0 unless rows.any?(&:key)

            rows.filter_map { |row| Text.width(row.key) if row.key }.max +
              (2 * PAD)
          end

          # @param width [Float] what the rows fill, at least {#width}
          # @return [Array<Hash>] the marks of rows whose corner is at
          #   `left`, `top`
          def draw(rows, left, top, width)
            keys = key_width(rows)
            split = left + keys
            marks = keys.positive? ? divider(split, top, height(rows)) : []
            rows.each_with_index.reduce([top, marks]) do |(y, out), (row, i)|
              out.concat(row_marks(row, [left, y, width], split, i))
              [y + row_height(row), out]
            end.last
          end

          private

          def cell_width(row)
            return width(row.inline.rows) if row.inline

            Text.width(row.value) + (2 * PAD)
          end

          def row_height(row)
            row.inline ? height(row.inline.rows) : ROW
          end

          def divider(split, top, height)
            [Marks.line([split, top], [split, top + height],
                        stroke: Marks::INK)]
          end

          def row_marks(row, frame, split, index)
            left, top, width = frame
            [*rule(left, top, width, index),
             *key_mark(row, left, top),
             *value_marks(row, [split, top, left + width])]
          end

          def rule(left, top, width, index)
            return [] unless index.positive?

            [Marks.line([left, top], [left + width, top], stroke: Marks::INK)]
          end

          def key_mark(row, left, top)
            return [] unless row.key

            [Marks.text(row.key, left + PAD, top + (ROW / 2))]
          end

          def value_marks(row, frame)
            split, top, right = frame
            if row.inline
              return draw(row.inline.rows, split, top, right - split)
            end

            [Marks.text(row.value, split + PAD, top + (ROW / 2))]
          end
        end
      end
    end
  end
end
