# frozen_string_literal: true

module Sirena
  module Layout
    # Where a C4 relationship leaves one box and meets the other, a port of
    # mermaid's getIntersectPoints. It aims at the other box's centre from
    # the near corner of this one, so the result can differ from a true
    # centre-to-centre crossing. Mermaid's choice, kept for parity.
    class C4Intersection
      # @param from [#x, #y, #width, #height] the box the line starts at
      # @param to [#x, #y, #width, #height] the box the line ends at
      # @return [Array<Array<Float>>] the start and end as [x, y] pairs
      def self.points(from, to)
        [leave(from, centre(to)), leave(to, centre(from))]
      end

      def self.centre(box)
        [box.x + (box.width / 2.0), box.y + (box.height / 2.0)]
      end

      def self.leave(box, target)
        axis_point(box, target) || diagonal_point(box, target) ||
          centre(box)
      end

      def self.axis_point(box, target)
        x_pos, y_pos = target
        mid_x, mid_y = centre(box)
        if box.y == y_pos
          [box.x < x_pos ? box.x + box.width : box.x, mid_y]
        elsif box.x == x_pos
          [mid_x, box.y < y_pos ? box.y + box.height : box.y]
        end
      end

      def self.diagonal_point(box, target)
        dx = (box.x - target[0]).abs
        dy = (box.y - target[1]).abs
        slope = dy / dx
        if (box.height / box.width) >= slope
          side_point(box, target, slope)
        else
          edge_point(box, target, dx / dy)
        end
      end

      def self.side_point(box, target, slope)
        mid_y = box.y + (box.height / 2.0)
        sign = box.y < target[1] ? 1 : -1
        x_pos = box.x > target[0] ? box.x : box.x + box.width
        [x_pos, mid_y + (sign * slope * box.width / 2.0)]
      end

      def self.edge_point(box, target, ratio)
        mid_x = box.x + (box.width / 2.0)
        sign = box.x > target[0] ? -1 : 1
        y_pos = box.y < target[1] ? box.y + box.height : box.y
        [mid_x + (sign * ratio * box.height / 2.0), y_pos]
      end

      private_class_method :centre, :leave, :axis_point, :diagonal_point,
                           :side_point, :edge_point
    end
  end
end
