# frozen_string_literal: true

module Sirena
  module Layout
    # The angular slice of the circle a branch of the tree is laid out in,
    # in degrees.
    class MindmapCoseWedge
      attr_reader :start_angle, :end_angle

      def initialize(start_angle, end_angle)
        @start_angle = start_angle
        @end_angle = end_angle
      end

      # @return [Float] the direction the branch's own node sits in
      def bearing
        (midpoint + start_angle).remainder(360)
      end

      # @param index [Integer] which child, counting from zero
      # @param count [Integer] how many children share this wedge
      # @return [MindmapCoseWedge] the child's share of this wedge
      def slice(index, count)
        step = (end_angle - start_angle).abs / count.to_f
        first = (start_angle + (index * step)).remainder(360)
        self.class.new(first, (first + step).remainder(360))
      end

      private

      def midpoint
        half = ((end_angle - start_angle) + 1) / 2.0
        half.negative? ? half + 180 : half
      end
    end
  end
end
