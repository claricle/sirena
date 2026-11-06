# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      # The points a relation's SVG path passes through, as a polyline close
      # enough to the drawn line to tell whether text lies across it. Lines
      # (`L`) contribute their end, curves (`C`, `Q`) a run of points along
      # the curve.
      module RelationPathPoints
        extend self

        STEPS = 16
        COMMAND = /([MLCQ])([^MLCQ]*)/
        ORDER = { "M" => 1, "L" => 1, "C" => 3, "Q" => 2 }.freeze
        private_constant :STEPS, :COMMAND, :ORDER

        # @param path [String, nil] SVG path data
        # @return [Array<Array(Float, Float)>]
        def call(path)
          path.to_s.scan(COMMAND).each_with_object([]) do |(command, args), out|
            coordinates = args.scan(/-?\d+(?:\.\d+)?/).map(&:to_f)
            group(command, coordinates).each do |controls|
              out.concat(curve(out.last, controls))
            end
          end
        end

        # @param points [Array<Array(Float, Float)>] a polyline
        # @param share [Float] 0 at its start, 1 at its end, by length
        # @return [Array(Float, Float), nil] the point that far along it
        def along(points, share)
          legs = points.each_cons(2).map do |from, to|
            [from, to, length(from, to)]
          end
          return points.first if legs.empty?

          remaining = legs.sum(&:last) * share
          legs.each do |from, to, span|
            return lerp(from, to, remaining / span) if remaining <= span

            remaining -= span
          end
          points.last
        end

        private

        def length(from, to)
          Math.hypot(to[0] - from[0], to[1] - from[1])
        end

        def lerp(from, to, share)
          reduce([from, to], share.nan? ? 0.0 : share).first
        end

        def group(command, coordinates)
          coordinates.each_slice(2).each_slice(ORDER.fetch(command)).to_a
        end

        # The points from `start` through `controls`, a Bezier when `start`
        # is known and more than the end is given.
        def curve(start, controls)
          return controls unless start && controls.size > 1

          (1..STEPS).map { |step| bezier(start, controls, step.fdiv(STEPS)) }
        end

        def bezier(start, controls, share)
          points = [start, *controls]
          points = reduce(points, share) while points.size > 1
          points.first
        end

        def reduce(points, share)
          points.each_cons(2).map do |from, to|
            [from[0] + ((to[0] - from[0]) * share),
             from[1] + ((to[1] - from[1]) * share)]
          end
        end
      end
    end
  end
end
