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
          # An empty class: its circle and name, then two 8-high compartments
          # ruled 32 and 40 below the top (measured on PlantUML 1.2026.6).
          CLASS_PAD = 32.0
          CLASS_HEIGHT = 48.0
          CLASS_RULES = [32.0, 40.0].freeze
          NAME_LEFT = 29.0
          SPOT_LEFT = 15.0
          SPOT_RADIUS = 11.0
          NAME_MIDDLE = 15.79
          # Of the height a larger font adds to a row, the part its baseline
          # drops (measured on PlantUML 1.2026.6: 5.8 of 7.06 at size 20).
          BASE_SHARE = 0.82
          Size = Data.define(:key, :value, :title, :width, :height)

          # @return [Size] the key and value column widths, the title band's
          #   height and the box's width and height
          def size(table)
            return inline_size(table) if table.kind == :inline
            return empty_size if table.kind == :tree && table.rows.empty?
            return class_size(table) if bare_class?(table)

            grid_size(table)
          end

          # @return [Float] the y of the middle of row `index` in a box at `top`
          def row_middle(table, index, top)
            top + size(table).title + offsets(table)[index] +
              (row_height(table, table.rows[index]) / 2)
          end

          # @return [Array<Hash>] the marks of the box with its corner at
          #   `left`, `top`, the outline last for a tree box
          def draw(table, left, top)
            box = size(table)
            corner = [left, top]
            return inline_marks(table, box, corner) if table.kind == :inline

            return class_marks(table, box, corner) if bare_class?(table)

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
                     height: title + offsets(table).last)
          end

          # A tree row grows with the largest `<size:..>` in its cells.
          def row_height(table, row)
            return ROW unless table.kind == :tree

            ROW + [Text.growth(row.key), Text.growth(row.value)].max
          end

          # @return [Array<Float>] each row's top below the title, and the
          #   rows' total height last
          def offsets(table)
            table.rows.each_with_object([0.0]) do |row, tops|
              tops << (tops.last + row_height(table, row))
            end
          end

          def bare_class?(table)
            table.kind == :class && table.rows.empty?
          end

          def bare_map?(table)
            table.kind == :map && table.rows.empty?
          end

          def class_size(table)
            width = Text.width(table.title.to_s) + CLASS_PAD
            Size.new(key: 0.0, value: width, title: CLASS_HEIGHT, width: width,
                     height: CLASS_HEIGHT)
          end

          def class_marks(table, box, corner)
            left, top = corner
            [background(table, box, corner), *class_spot(left, top),
             Marks.text(table.title, left + NAME_LEFT, top + NAME_MIDDLE,
                        anchor: "start"),
             *CLASS_RULES.map { |rule| class_rule(box, left, top + rule) }]
          end

          def class_rule(box, left, y)
            Marks.line([left + 1, y], [left + box.width - 1, y],
                       stroke: Marks::INK, width: 0.5)
          end

          # The circled C, drawn with the outline PlantUML's class diagrams use.
          def class_spot(left, top)
            require_relative "../../plantuml/class_header"
            glyph = PlantUML::ClassHeader.glyph(:class)
            centre = [left + SPOT_LEFT, top + (SPOT_RADIUS + 5.0)]
            [{ kind: :circle, cx: centre[0], cy: centre[1], r: SPOT_RADIUS,
               fill: glyph.fill, stroke: Marks::INK },
             { kind: :glyph, d: glyph.outline, fill: Marks::BLACK,
               transform: format("translate(%<x>.4f %<y>.4f)", x: centre[0],
                                                              y: centre[1]) }]
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
            return map_key_width(table) if table.kind == :map
            return 0.0 unless table.kind == :tree && table.keyed?

            widest(table.rows) do |r|
              Text.width(r.key.to_s, bold: true)
            end + (2 * PAD)
          end

          def values_width(table)
            return 0.0 if table.rows.empty?

            table.kind == :map ? map_width(table) : list_width(table)
          end

          # A map's key column is as wide as its widest key; a row without a
          # value (a link out) centres its key across the whole box instead.
          def map_key_width(table)
            valued = table.rows.reject { |r| r.value.empty? }
            return 0.0 if valued.empty?

            widest(valued) { |r| Text.width(r.key.to_s) } + (2 * PAD)
          end

          def map_width(table)
            valued, bare = table.rows.partition { |r| !r.value.empty? }
            [map_value_width(valued),
             map_alone_width(bare) - map_key_width(table)].max
          end

          def map_value_width(rows)
            widest(rows) { |r| Text.width(r.value) } + (2 * PAD)
          end

          def map_alone_width(rows)
            widest(rows) { |r| Text.width(r.key.to_s) } + (2 * PAD)
          end

          def list_width(table)
            widest(table.rows) { |r| Text.width(r.value) } + (2 * PAD)
          end

          def widest(rows, &)
            rows.map(&).max || 0.0
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

            return ROW unless table.rows.empty?

            bare_map?(table) ? ROW : LONE_TITLE
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
            return [title_text(table, box, corner)] if bare_map?(table)

            [title_text(table, box, corner), title_rule(box, corner)]
          end

          def title_text(table, box, corner)
            Marks.text(table.title, corner[0] + (box.width / 2),
                       corner[1] + ([box.title, ROW].min / 2), anchor: "middle")
          end

          def title_rule(box, corner)
            left, top = corner
            rule = top + [box.title, ROW].min
            Marks.line([left, rule], [left + box.width, rule],
                       stroke: Marks::INK, width: 0.5)
          end

          def rows_marks(table, box, corner)
            table.rows.each_with_index.flat_map do |row, i|
              at = [corner[0], corner[1] + box.title + offsets(table)[i]]
              row_marks(table, row, box, at, i)
            end
          end

          def row_marks(table, row, box, corner, index)
            case table.kind
            when :tree then tree_row(table, row, box, corner, index)
            when :map then map_row(row, box, corner, index)
            else [Marks.text(row.value, corner[0] + PAD + 2,
                             corner[1] + (ROW / 2))]
            end
          end

          def tree_row(table, row, box, corner, index)
            height = row_height(table, row)
            last = index == table.rows.size - 1
            [*highlight(row.style, box, corner, height),
             *tree_text(row, box, corner),
             *divider(box, corner, height),
             *separator(box, corner, last, height)]
          end

          def tree_text(row, box, corner)
            left, top = corner
            value = cell_text(row.value, left + box.key + PAD, top,
                              **ink(row.style, false))
            return [value] unless row.key

            [cell_text(row.key, left + PAD, top, **ink(row.style, true)), value]
          end

          # The text of a row whose top is `top`: centred in a plain row, and
          # sitting lower by most of what its own size adds to a taller one.
          def cell_text(content, left, top, **style)
            Marks.text(content, left,
                       top + (ROW / 2) + (BASE_SHARE * Text.growth(content)),
                       **style)
          end

          def divider(box, corner, height)
            return [] unless box.key.positive?

            left, top = corner
            [Marks.line([left + box.key, top], [left + box.key, top + height])]
          end

          def separator(box, corner, last, height)
            return [] if last

            left, top = corner
            [Marks.line([left, top + height], [left + box.width, top + height])]
          end

          def highlight(style, box, corner, height)
            return [] unless style

            paint = style[:background]
            [Marks.rect(corner[0] + 1.5, corner[1], box.width - 2, height,
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
            return map_link_cell(row, box, corner) if row.value.empty?

            split = left + box.key
            [cell_text(row.key, left + PAD, top),
             cell_text(row.value, split + PAD, top), map_split(split, top)]
          end

          # The key of a row that only links out, centred across the box.
          def map_link_cell(row, box, corner)
            [cell_text(row.key, corner[0] + (box.width / 2), corner[1],
                       anchor: "middle")]
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
