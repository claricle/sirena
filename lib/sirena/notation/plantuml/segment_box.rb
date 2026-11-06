# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      # Whether a line segment passes through a box (Liang-Barsky): the part
      # of the segment inside the box, if any, is a range of its length
      # narrowed axis by axis.
      module SegmentBox
        extend self

        # @param box [Array<Float>] left, top, right, bottom
        # @param from [Array(Float, Float)] one end of the segment
        # @param to [Array(Float, Float)] the other end
        def crosses?(box, from, to)
          span = [0.0, 1.0]
          [0, 1].all? do |axis|
            inside?(span, from[axis], to[axis], box[axis], box[axis + 2])
          end
        end

        private

        def inside?(span, start, finish, low, high)
          delta = finish - start
          return start.between?(low, high) if delta.zero?

          overlaps?(span, [(low - start) / delta, (high - start) / delta])
        end

        def overlaps?(span, bounds)
          first, last = bounds.minmax
          span[0] = [span[0], first].max
          span[1] = [span[1], last].min
          span[0] <= span[1]
        end
      end
    end
  end
end
