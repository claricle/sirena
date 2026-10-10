# frozen_string_literal: true

require_relative "mindmap_cose_geometry"

module Sirena
  module Layout
    # An edge between two bodies, measured between the box borders.
    class MindmapCoseLink
      attr_reader :source, :target, :length_x, :length_y, :length

      def initialize(source, target)
        @source = source
        @target = target
      end

      def other_end(body)
        body.equal?(source) ? target : source
      end

      # @return [Float, nil] the new length, or nil when the two boxes
      #   overlap, which leaves the edge without a spring force.
      def measure
        clip = MindmapCoseGeometry.clip_points(target, source)
        return unless clip

        @length_x = unit_floor(clip[0] - clip[2])
        @length_y = unit_floor(clip[1] - clip[3])
        @length = Math.sqrt((length_x * length_x) + (length_y * length_y))
      end

      private

      def unit_floor(value)
        value.abs < 1.0 ? (value <=> 0).to_f : value
      end
    end
  end
end
