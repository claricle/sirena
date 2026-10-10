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
        if box.y == y_pos
          [horizontal_exit_x(box, x_pos), centre(box)[1]]
        elsif box.x == x_pos
          [centre(box)[0], vertical_exit_y(box, y_pos)]
        end
      end

      def self.horizontal_exit_x(box, x_pos)
        box.x < x_pos ? box.x + box.width : box.x
      end

      def self.vertical_exit_y(box, y_pos)
        box.y < y_pos ? box.y + box.height : box.y
      end

      def self.diagonal_point(box, target)
        dx, dy = offsets(box, target)
        slope = dy.fdiv(dx)
        if box.height.fdiv(box.width) >= slope
          side_point(box, target, slope)
        else
          edge_point(box, target, dx.fdiv(dy))
        end
      end

      def self.offsets(box, target)
        [(box.x - target[0]).abs, (box.y - target[1]).abs]
      end

      def self.side_point(box, target, slope)
        sign = box.y < target[1] ? 1 : -1
        [side_x(box, target), centre(box)[1] + (sign * slope * box.width / 2.0)]
      end

      def self.side_x(box, target)
        box.x > target[0] ? box.x : box.x + box.width
      end

      def self.edge_point(box, target, ratio)
        sign = box.x > target[0] ? -1 : 1
        [centre(box)[0] + (sign * ratio * box.height / 2.0),
         vertical_exit_y(box, target[1])]
      end

      private_class_method :centre, :leave, :axis_point, :diagonal_point,
                           :side_point, :edge_point, :horizontal_exit_x,
                           :vertical_exit_y, :offsets, :side_x
    end
  end
end
