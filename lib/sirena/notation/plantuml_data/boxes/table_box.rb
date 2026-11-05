# frozen_string_literal: true

require_relative "inline_rows"
require_relative "marks"
require_relative "text"

module Sirena
  module Notation
    module PlantUMLData
      module Boxes
        # Measures a {Table} and draws it: JSON and YAML boxes as rows of
        # key and value, object and map boxes under a centred title.
        module TableBox
          extend self

          ROW = InlineRows::ROW
          PAD = 5.0
          TITLE_PAD = 7.0
          LONE_TITLE = 36.4883
          EMPTY_WIDTH = 30.0
          EMPTY_HEIGHT = 15.0
          Size = Data.define(:key, :value, :title, :width, :height)

          # @return [Size] the key and value column widths, the title band's
          #   height and the box's width and height
          def size(table)
            return inline_size(table) if table.kind == :inline
            return empty_size if table.kind == :tree && table.rows.empty?

            grid_size(table)
          end

          # @return [Float] the y of the middle of row `index` in a box at `top`
          def row_middle(table, index, top)
            top + size(table).title + (index * ROW) + (ROW / 2)
          end

          # @return [Array<Hash>] the marks of the box with its corner at
          #   `left`, `top`, the outline last for a tree box
          def draw(table, left, top)
            box = size(table)
            corner = [left, top]
            return inline_marks(table, box, corner) if table.kind == :inline

            [background(table, box, corner),
             *title_marks(table, box, corner),
             *rows_marks(table, box, corner),
             *outline(table, box, corner)]
          end

          private

          def grid_size(table)
            key = key_width(table)
            title = title_height(table)
            width = [key + values_width(table), title_width(table)].max
            Size.new(key: key, value: width - key, title: title, width: width,
                     height: title + (table.rows.size * ROW))
          end

          def inline_size(table)
            title = title_height(table)
            width = [InlineRows.width(table.rows), title_width(table)].max
            key = InlineRows.key_width(table.rows)
            Size.new(key: key, value: width - key, title: title, width: width,
                     height: title + InlineRows.height(table.rows))
          end

          def empty_size
            Size.new(key: 0.0, value: EMPTY_WIDTH, title: 0.0,
                     width: EMPTY_WIDTH, height: EMPTY_HEIGHT)
          end

          def inline_marks(table, box, corner)
            left, top = corner
            [background(table, box, corner), *title_marks(table, box, corner),
             *InlineRows.draw(table.rows, left, top + box.title, box.width)]
          end

          def key_width(table)
            return 0.0 unless table.kind == :tree && table.keyed?

            widest(table) { |r| Text.width(r.key.to_s, bold: true) } + (2 * PAD)
          end

          def values_width(table)
            return 0.0 if table.rows.empty?

            table.kind == :map ? map_width(table) : list_width(table)
          end

          def map_width(table)
            widest(table) { |r| Text.width(r.key.to_s) + Text.width(r.value) } +
              (4 * PAD)
          end

          def list_width(table)
            widest(table) { |r| Text.width(r.value) } + (2 * PAD)
          end

          def widest(table, &)
            table.rows.map(&).max
          end

          def titled?(table)
            !table.title.nil? && table.kind != :tree
          end

          def title_width(table)
            return 0.0 unless titled?(table)

            Text.width(table.title.to_s) + (2 * TITLE_PAD)
          end

          def title_height(table)
            return 0.0 unless titled?(table)

            table.rows.empty? ? LONE_TITLE : ROW
          end

          def background(table, box, corner)
            left, top = corner
            if table.kind == :tree
              Marks.rect(left, top, box.width, box.height, stroke: Marks::PAPER)
            else
              Marks.rect(left, top, box.width, box.height, rx: 2.5,
                                                           stroke_width: 0.5)
            end
          end

          def outline(table, box, corner)
            return [] unless table.kind == :tree

            [Marks.rect(corner[0], corner[1], box.width, box.height,
                        fill: "none", stroke: Marks::BLACK)]
          end

          def title_marks(table, box, corner)
            return [] unless box.title.positive?

            [title_text(table, box, corner), title_rule(box, corner)]
          end

          def title_text(table, box, corner)
            Marks.text(table.title, corner[0] + (box.width / 2),
                       corner[1] + ([box.title, ROW].min / 2), anchor: "middle")
          end

          def title_rule(box, corner)
            left, top = corner
            Marks.line([left, top + box.title],
                       [left + box.width, top + box.title],
                       stroke: Marks::INK, width: 0.5)
          end

          def rows_marks(table, box, corner)
            table.rows.each_with_index.flat_map do |row, i|
              at = [corner[0], corner[1] + box.title + (i * ROW)]
              row_marks(table, row, box, at, i)
            end
          end

          def row_marks(table, row, box, corner, index)
            case table.kind
            when :tree then tree_row(row, box, corner,
                                     index == table.rows.size - 1)
            when :map then map_row(row, box, corner, index)
            else [Marks.text(row.value, corner[0] + PAD + 2,
                             corner[1] + (ROW / 2))]
            end
          end

          def tree_row(row, box, corner, last)
            [*highlight(row.style, box, corner),
             *tree_text(row, box, corner),
             *divider(box, corner),
             *separator(box, corner, last)]
          end

          def tree_text(row, box, corner)
            left, top = corner
            value = cell_text(row.value, left + box.key + PAD, top,
                              **ink(row.style, false))
            return [value] unless row.key

            [cell_text(row.key, left + PAD, top, **ink(row.style, true)), value]
          end

          # The text of a row whose top is `top`, vertically centred.
          def cell_text(content, left, top, **style)
            Marks.text(content, left, top + (ROW / 2), **style)
          end

          def divider(box, corner)
            return [] unless box.key.positive?

            left, top = corner
            [Marks.line([left + box.key, top], [left + box.key, top + ROW])]
          end

          def separator(box, corner, last)
            return [] if last

            left, top = corner
            [Marks.line([left, top + ROW], [left + box.width, top + ROW])]
          end

          def highlight(style, box, corner)
            return [] unless style

            paint = style[:background]
            [Marks.rect(corner[0] + 1.5, corner[1], box.width - 2, ROW,
                        rx: 2, fill: paint, stroke: paint, stroke_width: 1)]
          end

          def map_row(row, box, corner, index)
            [*map_rule(box, corner, index), *map_cells(row, box, corner)]
          end

          def map_rule(box, corner, index)
            return [] unless index.positive?

            left, top = corner
            [Marks.line([left, top], [left + box.width, top],
                        stroke: Marks::INK)]
          end

          def map_cells(row, box, corner)
            left, top = corner
            split = left + (box.width / 2)
            if row.value.empty?
              return [cell_text(row.key, split, top, anchor: "middle")]
            end

            [cell_text(row.key, left + PAD, top),
             cell_text(row.value, split + PAD, top), map_split(split, top)]
          end

          def map_split(split, top)
            Marks.line([split, top], [split, top + ROW], stroke: Marks::INK)
          end

          def ink(style, bold)
            return { bold: bold } unless style

            { bold: bold || style[:style] == "bold", fill: style[:color],
              italic: style[:style] == "italic" }
          end
        end
      end
    end
  end
end
