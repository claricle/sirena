# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module NodeGraph
        # The points the links across ranks pass through, in final
        # coordinates.
        class Paths
          # @param axis [Integer] 0 when ranks run left to right, else 1
          def initialize(axis)
            @axis = axis
            @through = {}
          end

          # Notes the points of a scope laid out at `origin`.
          #
          # @param paths [Hash{Array => Array<Array(Float, Float)>}]
          def record(paths, origin)
            paths.each do |ends, points|
              @through[ends] = points.map do |point|
                point.zip(origin).map(&:sum)
              end
            end
          end

          # @param edge [Edge]
          # @param start [Array<Float>] the middle of the box it leaves
          # @return [Array<Array<Float>>] its points, nearest `start` first
          def between(edge, start)
            points = @through.find { |ends, _| spans?(ends, edge) }&.last
            (points || []).sort_by { |point| (point[@axis] - start[@axis]).abs }
          end

          private

          def spans?(ends, edge)
            [[edge.from, edge.to], [edge.to, edge.from]].any? do |pair|
              pair.zip(ends).all? do |node, scope|
                node.equal?(scope) || node.ancestors.include?(scope)
              end
            end
          end
        end
      end
    end
  end
end
