# frozen_string_literal: true

require_relative "marks"
require_relative "scene"
require_relative "table_box"

module Sirena
  module Notation
    module PlantUMLData
      module Boxes
        # Lays a JSON or YAML table tree out left to right: a table's
        # children stand in a column to its right, stacked, and the table
        # is centred on them. A row that has a child links to it.
        class TreeLayout
          GAP_X = 37.0
          GAP_Y = 18.5
          MARGIN = 10.0
          private_constant :GAP_X, :GAP_Y, :MARGIN

          # @param diagram [Diagram] one root table
          # @return [Scene]
          def call(diagram, **)
            @marks = []
            @links = []
            @right = 0.0
            span, = place(diagram.tables.first, MARGIN, MARGIN)
            Scene.new(width: @right + MARGIN + 1,
                      height: span + (2 * MARGIN) + 1, marks: @marks + @links)
          end

          private

          # @return [Array(Float, Float)] the height of the table's subtree
          #   and the y the table itself was drawn at
          def place(table, left, top)
            box = TableBox.size(table)
            reach, targets = children(table, left + box.width + GAP_X, top)
            span = [reach, box.height].max
            level = top + ((span - box.height) / 2)
            draw(table, box, [left, level], targets)
            [span, level]
          end

          def draw(table, box, corner, targets)
            @right = [@right, corner[0] + box.width].max
            @marks.concat(TableBox.draw(table, *corner))
            link_rows(table, targets, [corner[0] + box.width, corner[1]])
          end

          def children(table, left, top)
            cursor = top
            targets = table.rows.select(&:child).to_h do |row|
              span, level = place(row.child, left, cursor)
              cursor += span + GAP_Y
              [row, [left, middle(row.child, level)]]
            end
            [[cursor - GAP_Y - top, 0].max, targets]
          end

          def middle(table, level)
            level + (TableBox.size(table).height / 2.0)
          end

          def link_rows(table, targets, corner)
            table.rows.each_with_index do |row, i|
              to = targets[row] or next
              link(
                [corner[0] - 11.6, TableBox.row_middle(table, i, corner[1])], to
              )
            end
          end

          def link(from, to)
            @links << Marks.curve(from, to, dashed: true)
            @links << Marks.arrowhead(to)
            @links << Marks.dot(from)
          end
        end
      end
    end
  end
end
