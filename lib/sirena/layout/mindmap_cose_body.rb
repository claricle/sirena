# frozen_string_literal: true

module Sirena
  module Layout
    # One node of the force-directed mindmap layout: a box with the forces
    # accumulated on it during an iteration.
    class MindmapCoseBody
      attr_reader :id, :width, :height, :links
      attr_accessor :x, :y, :spring_x, :spring_y, :repulsion_x, :repulsion_y,
                    :cells, :surrounding

      def initialize(id, width, height)
        @id = id
        @width = width.to_f
        @height = height.to_f
        @x = 0.0
        @y = 0.0
        @links = []
        @cells = [0, 0, 0, 0]
        @surrounding = []
        clear_forces
      end

      def right
        x + width
      end

      def bottom
        y + height
      end

      def center_x
        x + (width / 2)
      end

      def center_y
        y + (height / 2)
      end

      def diagonal
        Math.sqrt((width * width) + (height * height))
      end

      def center=(point)
        @x = point[0] - (width / 2)
        @y = point[1] - (height / 2)
      end

      def neighbors
        links.map { |link| link.other_end(self) }.uniq
      end

      # Applies the accumulated forces, clamped to the cooling-scaled
      # displacement limit, and returns the distance moved.
      def move(cooling, max_displacement)
        limit = cooling * max_displacement
        moved_x = clamp(cooling * (spring_x + repulsion_x), limit)
        moved_y = clamp(cooling * (spring_y + repulsion_y), limit)
        @x += moved_x
        @y += moved_y
        clear_forces
        moved_x.abs + moved_y.abs
      end

      private

      def clamp(displacement, limit)
        return displacement unless displacement.abs > limit

        limit * (displacement <=> 0)
      end

      def clear_forces
        @spring_x = 0.0
        @spring_y = 0.0
        @repulsion_x = 0.0
        @repulsion_y = 0.0
      end
    end
  end
end
