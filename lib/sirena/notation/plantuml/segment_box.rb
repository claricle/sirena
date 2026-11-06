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

        # Whether the segment lies within `gap` of the box, measured straight
        # between them rather than along each axis, so a corner of the box is
        # no further off than its sides.
        # @param gap [Float] the farthest the segment may be from the box
        def within?(box, from, to, gap)
          distance(box, from, to) <= gap
        end

        private

        # Zero when the segment crosses the box; otherwise the shortest
        # reach is between a corner of the box and the segment, or between an
        # end of the segment and the box.
        def distance(box, from, to)
          return 0.0 if crosses?(box, from, to)

          corners = [box.values_at(0, 1), box.values_at(2, 1),
                     box.values_at(2, 3), box.values_at(0, 3)]
          [*corners.map { |corner| to_segment(corner, from, to) },
           *[from, to].map { |end_point| to_box(end_point, box) }].min
        end

        def to_box(point, box)
          Math.hypot([box[0] - point[0], 0, point[0] - box[2]].max,
                     [box[1] - point[1], 0, point[1] - box[3]].max)
        end

        def to_segment(point, from, to)
          near = nearest_on(point, from, to)
          Math.hypot(point[0] - near[0], point[1] - near[1])
        end

        def nearest_on(point, from, to)
          run = to.zip(from).map { |end_at, start| end_at - start }
          share = share_of(point.zip(from).map { |at, start| at - start }, run)
          from.zip(run).map { |start, part| start + (share * part) }
        end

        # How far along `run` the point `gone` from its start lies, kept
        # within the segment.
        def share_of(gone, run)
          length = run.sum { |part| part * part }
          return 0.0 if length.zero?

          (gone.zip(run).sum { |at, part| at * part } / length).clamp(0.0, 1.0)
        end

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
