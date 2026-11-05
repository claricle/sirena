# frozen_string_literal: true

require_relative "layout"

module Sirena
  module Notation
    module PlantUML
      module Tree
        # PlantUML's mindmap: the root in the middle, its right-hand
        # branches growing right and its left-hand ones growing left, every
        # parent centred on its children and joined to them by a curve.
        class MindmapLayout < Layout
          SIBLING_GAP = 20.0
          LEVEL_GAP = 50.0
          LEAD = 10.0
          BEND = 25.0
          private_constant :SIBLING_GAP, :LEVEL_GAP, :LEAD, :BEND

          private

          def font_size
            14.0
          end

          def gap_between_trees
            SIBLING_GAP
          end

          def corner_radius
            12.5
          end

          # A subtree measured on its own: where each child sits relative to
          # the item's centre, and how far the subtree reaches above and
          # below that centre at each depth.
          Subtree = Struct.new(:item, :children, :offsets, :contour)
          private_constant :Subtree

          def place_tree(root, top)
            sides = fan_sides(root)
            half = root.height / 2.0
            low, high = extent(sides, half)
            centre = top - low
            place_sides(box(root, 0.0, centre - half), sides)
            centre + high
          end

          def extent(sides, half)
            reach = sides.flat_map { |(_, _, deep), _| deep.flatten }
            [[reach.min, -half].compact.min, [reach.max, half].compact.max]
          end

          def fan_sides(root)
            right, left = root.children.partition { |c| c.side == "right" }
            [[fan(right), 1], [fan(left), -1]]
          end

          def place_sides(hub, sides)
            sides.each do |(subs, offsets, _), direction|
              place(hub, subs, offsets, direction)
            end
          end

          def tree(item)
            subs, offsets, deep = fan(item.children)
            half = item.height / 2.0
            Subtree.new(item, subs, offsets, [[-half, half]] + deep)
          end

          # Subtrees of siblings packed top to bottom, each as close to the
          # one before as their contours allow, and centred on the middle of
          # what they cover. Returns [subtrees, offsets from that middle,
          # contour about it].
          def fan(items)
            subs = items.map { |item| tree(item) }
            return [subs, [], []] if subs.empty?

            [subs, *recentre(*stack(subs))]
          end

          def recentre(offsets, covered)
            mid = (covered.flatten.min + covered.flatten.max) / 2.0
            [offsets.map { |o| o - mid },
             covered.map { |top, bottom| [top - mid, bottom - mid] }]
          end

          def stack(subs)
            offsets = []
            covered = []
            subs.each do |sub|
              offset = covered.empty? ? 0.0 : clearance(covered, sub.contour)
              offsets << offset
              absorb(covered, sub.contour, offset)
            end
            [offsets, covered]
          end

          def clearance(covered, contour)
            shared = [covered.length, contour.length].min
            (0...shared).map do |depth|
              covered[depth].last + SIBLING_GAP - contour[depth].first
            end.max
          end

          def absorb(covered, contour, offset)
            contour.each_with_index do |(top, bottom), depth|
              reach = [top + offset, bottom + offset]
              covered[depth] = if covered[depth]
                                 [[covered[depth].first, reach.first].min,
                                  [covered[depth].last, reach.last].max]
                               else
                                 reach
                               end
            end
          end

          def place(parent, subs, offsets, direction)
            subs.zip(offsets).each do |sub, offset|
              child = child_box(parent, sub.item, direction,
                                parent.mid_y + offset)
              join(parent, child, direction)
              place(child, sub.children, sub.offsets, direction)
            end
          end

          def child_box(parent, item, direction, centre)
            left = if direction.positive?
                     parent.right + LEVEL_GAP
                   else
                     parent.x - LEVEL_GAP - item.width
                   end
            box(item, left, centre - (item.height / 2.0))
          end

          def join(parent, child, direction)
            start = direction.positive? ? parent.right : parent.x
            stop = direction.positive? ? child.x : child.right
            curve(connector(start, parent.mid_y, stop, child.mid_y, direction))
          end

          def connector(from_x, from_y, to_x, to_y, direction)
            lead = direction * LEAD
            bend = direction * BEND
            "M#{point(from_x, from_y)} L#{point(from_x + lead, from_y)} " \
              "C#{point(from_x + bend, from_y)} #{point(to_x - bend, to_y)} " \
              "#{point(to_x - lead, to_y)} L#{point(to_x, to_y)}"
          end

          def point(x_pos, y_pos)
            "#{x_pos.round(3)},#{y_pos.round(3)}"
          end
        end
      end
    end
  end
end
