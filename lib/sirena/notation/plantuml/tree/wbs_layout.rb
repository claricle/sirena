# frozen_string_literal: true

require_relative "layout"

module Sirena
  module Notation
    module PlantUML
      module Tree
        # PlantUML's work breakdown structure: the root on top, its children
        # in a row under a bus line, and every deeper level hanging in a
        # column from the middle of its parent with short stubs to each box.
        class WbsLayout < Layout
          ROW_GAP = 40.0
          COLUMN_GAP = 15.0
          BLOCK_GAP = 20.0
          STUB = 10.0
          private_constant :ROW_GAP, :COLUMN_GAP, :BLOCK_GAP, :STUB

          private

          def font_size
            12.0
          end

          def gap_between_trees
            BLOCK_GAP
          end

          # The jar leaves a boxless node's text one above and below.
          def boxless_pad_y
            1.0
          end

          def stroke_width
            1.5
          end

          def place_tree(root, top)
            blocks = row_blocks(root, top)
            hub = box(root, hub_centre(blocks) - (root.width / 2.0), top)
            bus(hub, blocks)
            [top + root.height, *blocks.map(&:bottom)].max
          end

          def row_blocks(root, top)
            row_top = top + root.height + ROW_GAP
            root.children.map { |child| row_block(child, row_top) }
          end

          def hub_centre(blocks)
            return 0.0 if blocks.empty?

            (blocks.first.center + blocks.last.center) / 2.0
          end

          # A first-level child with its descendants, left to right.
          Block = Struct.new(:box, :bottom) do
            def center
              box.x + (box.item.width / 2.0)
            end
          end
          private_constant :Block

          def row_block(item, top)
            boxes_from = @boxes.size
            segments_from = @segments.size
            placed = box(item, 0.0, top)
            bottom = hang(placed)
            align_row(@boxes[boxes_from..], segments_from)
            Block.new(placed, bottom)
          end

          def align_row(members, segments_from)
            offset = (@row_end || 0.0) - members.map(&:x).min
            members.each { |member| member.x += offset }
            shift_segments(segments_from, offset)
            @row_end = members.map(&:right).max + BLOCK_GAP
          end

          def shift_segments(from, offset)
            (from...@segments.length).each do |index|
              @segments[index] = shift_path(@segments[index], offset)
            end
          end

          def bus(hub, blocks)
            return if blocks.empty?

            mid = hub.item.height + hub.y + (ROW_GAP / 2.0)
            trunk(hub, mid)
            branches(blocks, mid)
          end

          def trunk(hub, mid)
            centre = hub.x + (hub.item.width / 2.0)
            segment(centre, hub.y + hub.item.height, centre, mid, 0)
          end

          def branches(blocks, mid)
            xs = blocks.map(&:center)
            segment(xs.min, mid, xs.max, mid, 0) if xs.min != xs.max
            blocks.each { |b| segment(b.center, mid, b.center, b.box.y, 0) }
          end

          # Hangs the children of a placed box under it; returns the bottom
          # of the lowest thing placed.
          def hang(parent)
            item = parent.item
            bottom = parent.y + item.height
            return bottom if item.children.empty?

            centre = parent.x + (item.width / 2.0)
            ends = hang_columns(parent, centre, bottom + COLUMN_GAP)
            join_columns(centre, bottom, ends, parent_depth(item))
          end

          # The depth a connector under this item is styled by.
          def parent_depth(item)
            item.level - 1
          end

          def hang_columns(parent, centre, top)
            right, left = parent.item.children.partition do |child|
              child.side == "right"
            end
            [column(parent, right, centre, top, 1),
             column(parent, left, centre, top, -1)]
          end

          # Joins the columns' last boxes to the parent; returns the lowest
          # bottom.
          def join_columns(centre, from, ends, depth)
            last_centre = ends.filter_map(&:last).max
            segment(centre, from, centre, last_centre, depth) if last_centre
            ends.map(&:first).max
          end

          # Stacks children in one column; returns [bottom, last centre].
          def column(_parent, items, centre, top, direction)
            cursor = top
            last = nil
            lowest = top - COLUMN_GAP
            items.each do |item|
              placed = stub_box(item, centre, cursor, direction)
              last = placed.mid_y
              lowest = hang(placed)
              cursor = lowest + COLUMN_GAP
            end
            [lowest, last]
          end

          def stub_box(item, mid, cursor, direction)
            edge = direction.positive? ? mid + STUB : mid - STUB - item.width
            placed = box(item, edge, cursor)
            reach = direction.positive? ? placed.x : placed.right
            segment(mid, placed.mid_y, reach, placed.mid_y,
                    parent_depth(item) - 1)
            placed
          end
        end
      end
    end
  end
end
