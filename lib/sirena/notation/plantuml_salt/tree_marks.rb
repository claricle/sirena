# frozen_string_literal: true

require_relative "box"
require_relative "mark"

module Sirena
  module Notation
    module PlantUMLSalt
      # What PlantUML adds around a `{T` tree table, in its own grey: a
      # small node mark on every row that has children, an elbow
      # connector from each row up to its parent, and the rules the
      # modifier asks for (`!` column bars, `-` row rules, `#` both, `+`
      # a frame). A bar or rule runs the full width or height, edges
      # included.
      module TreeMarks
        TREE_INK = "#888888"
        NODE = 2.0
        NODE_RISE = 1.0
        ELBOW_GAP = 2.0
        NODE_LEFT = 6.0
        ROW_HEIGHT = 14.1328
        PAD = 5.0
        INDENT = 10.0
        TEXT_DROP = 7.6

        private

        def tree_decor(block, columns, area)
          tops = row_tops(block, area)
          connectors(block, tops, area)
          rules(block, columns, area, tops)
        end

        def row_tops(block, area)
          top = area.top
          block.rows.map do |row|
            top.tap { top += row_height(block, row) }
          end << top
        end

        def connectors(block, tops, area)
          rows = block.rows
          rows.each_index do |index|
            parent = parent_index(rows, index)
            node(rows, index, tops, area) if parent_of?(rows, index)
            elbow(rows, parent, index, tops, area) if parent
          end
        end

        def parent_index(rows, index)
          depth = rows[index].depth
          return if depth < 2

          (index - 1).downto(0).find { |back| rows[back].depth < depth }
        end

        def parent_of?(rows, index)
          rows[index].depth.positive? && rows[index + 1] &&
            rows[index + 1].depth > rows[index].depth
        end

        def centre_y(tops, index)
          (tops[index] + tops[index + 1]) / 2
        end

        def centre_x(row, area)
          area.left + (row.depth * INDENT) - NODE_LEFT
        end

        def node(rows, index, tops, area)
          x = centre_x(rows[index], area)
          y = centre_y(tops, index)
          box = Box.new(x - NODE_RISE, y - NODE_RISE, NODE, NODE)
          @marks << Mark.new(:rect, box, fill: "node", ink: TREE_INK)
        end

        def elbow(rows, parent, index, tops, area)
          x = centre_x(rows[parent], area)
          from = centre_y(tops, parent) + NODE
          to = centre_y(tops, index)
          @marks << grey(x, from, 0.0, to - from)
          @marks << grey(x, to, reach(rows[index], area) - x, 0.0)
        end

        def reach(row, area)
          centre_x(row, area) - ELBOW_GAP
        end

        def grey(left, top, width, height)
          Mark.new(:line, Box.new(left, top, width, height), ink: TREE_INK)
        end

        def rules(block, columns, area, tops)
          if block.border?
            @marks << Mark.new(:rect, area, fill: "frame", ink: TREE_INK)
          end
          bars(columns, area) if block.grid? || block.column_lines?
          bands(tops, area) if block.grid? || block.row_lines?
        end

        def bands(tops, area)
          tops.each { |top| @marks << grey(area.left, top, area.width, 0.0) }
        end

        def bars(columns, area)
          left = area.left
          [0.0, *columns].each do |width|
            left += width
            @marks << grey(left, area.top, 0.0, area.height)
          end
        end
      end
    end
  end
end
