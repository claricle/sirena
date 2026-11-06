# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module NodeGraph
        # A point a link across several ranks passes through in a rank it
        # skips, as the JAR's virtual node for it. It has no size: it only
        # keeps the link's place in the order of the rank.
        Waypoint = Class.new

        # Gives each link that skips ranks a {Waypoint} in every rank it
        # skips, and the shorter links of the chain they make.
        class SkippedRanks
          # @return [Hash{Array => Array<Waypoint>}] for each `[from, to]`
          #   that spans more than one rank, its waypoints from the rank
          #   after `from`
          attr_reader :chains

          # @return [Array<Array>] the links the order of the ranks is
          #   settled by, each `[from, to, step]`
          attr_reader :links

          # @param layers [Array<Array<Object>>] the items of each rank, which
          #   gain the waypoints
          # @param rank [Hash{Object => Integer}]
          # @param pairs [Array<Array>] every link, `[from, to, step]`
          # @param kept [Array<Array>] the links that close no cycle
          def initialize(layers, rank, pairs, kept)
            @layers = layers
            @rank = rank
            @kept = kept
            @chains = {}
            @links = pairs.flat_map { |pair| chained(pair) }
          end

          private

          def chained(pair)
            from, to, = pair
            span = @rank[to] - @rank[from]
            return [pair] unless span > 1 && kept?(pair)

            points = @chains[[from, to]] = waypoints(from, span - 1)
            [from, *points, to].each_cons(2).map { |a, b| [a, b, 1] }
          end

          def kept?(pair)
            @kept.any? { |link| link.equal?(pair) }
          end

          def waypoints(from, count)
            Array.new(count) { Waypoint.new }.each_with_index do |point, at|
              @layers[@rank[from] + 1 + at] << point
            end
          end
        end
      end
    end
  end
end
