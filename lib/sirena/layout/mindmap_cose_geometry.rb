# frozen_string_literal: true

module Sirena
  module Layout
    # Box geometry of the mindmap force layout: overlap, the border points
    # where the line between two box centres leaves each box, and how far
    # two overlapping boxes must move apart.
    module MindmapCoseGeometry
      # [slope sign, first side to test] for the first box, keyed by whether
      # the other box lies to its left and above it. The second box uses
      # the side two steps round.
      CARDINAL_LINES = {
        [true, true] => [1, 4],
        [true, false] => [-1, 3],
        [false, true] => [-1, 1],
        [false, false] => [1, 2],
      }.freeze

      module_function

      # @return [Array<Float>] [left, top, right, bottom] around +bodies+
      def bounding_box(bodies)
        [bodies.map(&:x).min, bodies.map(&:y).min,
         bodies.map(&:right).max, bodies.map(&:bottom).max]
      end

      def intersects?(first, second)
        !(first.right < second.x || first.bottom < second.y ||
          second.right < first.x || second.bottom < first.y)
      end

      # @return [Array<Float>, nil] [x1, y1, x2, y2] where the centre line
      #   leaves +first+ and +second+, or nil when the boxes overlap.
      def clip_points(first, second)
        return nil if intersects?(first, second)

        aligned_clip(first, second) || slanted_clip(first, second)
      end

      def aligned_clip(first, second)
        if first.center_x == second.center_x
          vertical_clip(first, second)
        elsif first.center_y == second.center_y
          horizontal_clip(first, second)
        end
      end

      def vertical_clip(first, second)
        x1 = first.center_x
        x2 = second.center_x
        if first.center_y > second.center_y
          [x1, first.y, x2, second.bottom]
        else
          [x1, first.bottom, x2, second.y]
        end
      end

      def horizontal_clip(first, second)
        y1 = first.center_y
        y2 = second.center_y
        if first.center_x > second.center_x
          [first.x, y1, second.right, y2]
        else
          [first.right, y1, second.x, y2]
        end
      end

      def slanted_clip(first, second)
        slope = slope_between(first, second)
        left_up = [first.center_x > second.center_x,
                   first.center_y > second.center_y]
        border_point(first, slope, left_up, second_box: false) +
          border_point(second, slope, left_up, second_box: true)
      end

      def slope_between(first, second)
        rise = second.center_y - first.center_y
        run = second.center_x - first.center_x
        rise / run
      end

      def border_point(box, slope, left_up, second_box:)
        other_left = second_box ? !left_up[0] : left_up[0]
        corner = corner_point(box, slope, other_left)
        return corner if corner

        sign, line = CARDINAL_LINES.fetch(left_up)
        line = ((line + 1) % 4) + 1 if second_box
        side_point(box, slope, cardinal(sign * box_slope(box), slope, line))
      end

      def box_slope(box)
        box.height / box.width
      end

      def corner_point(box, slope, other_left)
        diagonal = box_slope(box)
        if -diagonal == slope
          other_left ? [box.x, box.bottom] : [box.right, box.y]
        elsif diagonal == slope
          other_left ? [box.x, box.y] : [box.right, box.bottom]
        end
      end

      def cardinal(box_slope, slope, line)
        box_slope > slope ? line : 1 + (line % 4)
      end

      def side_point(box, slope, direction)
        case direction
        when 1 then top_point(box, slope)
        when 2 then right_point(box, slope)
        when 3 then bottom_point(box, slope)
        else left_point(box, slope)
        end
      end

      def top_point(box, slope)
        [box.center_x + (-box.half_height / slope), box.y]
      end

      def right_point(box, slope)
        [box.right, box.center_y + (box.half_width * slope)]
      end

      def bottom_point(box, slope)
        [box.center_x + (box.half_height / slope), box.bottom]
      end

      def left_point(box, slope)
        [box.x, box.center_y + (-box.half_width * slope)]
      end

      # How far each of two overlapping boxes is pushed along each axis.
      #
      # @return [Array<Float>] [x, y] separation for the first box
      def separation(first, second, buffer)
        move_x, move_y = overlap_shift(first, second)
        direction_x = direction(first.center_x, second.center_x)
        direction_y = direction(first.center_y, second.center_y)
        [push(direction_x, move_x, buffer), push(direction_y, move_y, buffer)]
      end

      def push(direction, move, buffer)
        -1 * direction * ((move / 2) + buffer)
      end

      # The overlap along the axis it is cheaper to separate on, and the
      # matching movement along the other axis.
      def overlap_shift(first, second)
        overlap_x, overlap_y = overlaps(first, second)
        slope = centre_slope(first, second)
        move_x = overlap_y / slope
        if overlap_x < move_x
          [overlap_x, slope * overlap_x]
        else
          [move_x, overlap_y]
        end
      end

      def direction(first_centre, second_centre)
        first_centre < second_centre ? -1 : 1
      end

      def centre_slope(first, second)
        same_row = first.center_y == second.center_y
        same_column = first.center_x == second.center_x
        return 1.0 if same_row && same_column

        slope_between(first, second).abs
      end

      def overlaps(first, second)
        [axis_overlap(first.x, first.right, second.x, second.right),
         axis_overlap(first.y, first.bottom, second.y, second.bottom)]
      end

      def axis_overlap(low_a, high_a, low_b, high_b)
        overlap = [high_a, high_b].min - [low_a, low_b].max
        if low_a <= low_b && high_a >= high_b
          overlap + [low_b - low_a, high_a - high_b].min
        elsif low_b <= low_a && high_b >= high_a
          overlap + [low_a - low_b, high_b - high_a].min
        else
          overlap
        end
      end
    end
  end
end
