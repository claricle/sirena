# frozen_string_literal: true

require_relative "routes"

module Sirena
  module Notation
    module PlantUML
      module State
        # The transitions one container's layout is given, as joins between
        # its rows. A transition between composites that share ranks is left
        # out, so it does not stack them.
        class LevelEdges
          # @param edges [Array<Hash>] every transition of the graph
          # @param parent [Hash{String=>String}] the container of each state
          # @param ranking [Ranking]
          def initialize(edges, parent, ranking)
            @edges = edges
            @parent = parent
            @ranking = ranking
          end

          # @param rows [Array<Row>] the container's rows
          # @return [Array<Hash>] ELK edges between row ids
          def of(rows)
            unit = unit_ids(rows)
            kept, peers = joins(unit).partition do |_, pair|
              !@ranking.overlap?(*pair)
            end
            elk = elk_edges(majority(kept), unit)
            joined = elk + entries(elk, peer_pairs(peers, unit))
            peers.empty? ? joined : by_target(joined, rows)
          end

          def elk_edges(joined, unit)
            joined.filter_map { |edge, pair| elk_edge(edge, pair, unit) }
          end

          def peer_pairs(peers, unit)
            peers.map { |_, pair| pair.map { |id| unit[id] } }
          end

          # Edges into the rows listed first come first, so ELK places
          # those rows first.
          def by_target(edges, rows)
            ids = rows.map(&:id)
            edges.sort_by.with_index do |edge, at|
              [ids.index(edge[:targets].first), at]
            end
          end

          # @param rows [Array<Row>] the container's rows
          # @return [Array<String>] the ids of rows PlantUML draws beside a
          #   row one of its transitions joins, in the order given
          def peer_ids(rows)
            unit = unit_ids(rows)
            linked = joins(unit).map(&:last).select do |pair|
              @ranking.overlap?(*pair)
            end
            rows.map(&:id) & linked.flatten.map { |id| unit[id] }
          end

          private

          # Of two states joined both ways, graphviz keeps the way most
          # transitions run and reverses the rest, so the states rank by the
          # majority; an even split keeps both.
          def majority(joined)
            counts = joined.map(&:last).tally
            joined.reject do |_, pair|
              counts[pair] < counts.fetch(pair.reverse, 0)
            end
          end

          def unit_ids(rows)
            rows.each_with_object({}) do |row, found|
              row.nodes.each { |node| found[node[:id]] = row.id }
            end
          end

          def joins(unit)
            @edges.filter_map do |edge|
              pair = Routes.level_pair(edge, @parent, unit.keys)
              [edge, pair] if pair
            end
          end

          def elk_edge(edge, pair, unit)
            from, to = pair.map { |id| unit[id] }
            return if from == to

            { id: edge.object_id.to_s, sources: [from], targets: [to] }
          end

          # A composite with nothing leading to it enters at the rank of
          # the peer it stands beside.
          def entries(elk, peers)
            peers.flat_map { |pair| [pair, pair.reverse] }
              .flat_map { |mine, other| enter(elk, mine, other) }
          end

          def enter(elk, mine, other)
            return [] if elk.any? { |found| found[:targets] == [mine] }

            elk.select { |found| found[:targets] == [other] }.map do |found|
              { id: "#{found[:id]}>#{mine}", sources: found[:sources],
                targets: [mine] }
            end
          end
        end
      end
    end
  end
end
