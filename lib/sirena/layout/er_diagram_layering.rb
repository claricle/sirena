# frozen_string_literal: true

module Sirena
  module Layout
    # Gives each entity a rank (a row of the diagram), the way dagre does
    # for mmdc: every relationship spans at least two ranks, so that it has
    # a middle rank to hold its label.
    #
    # APPROXIMATION: dagre ranks with network simplex. This starts from the
    # longest path and then moves a node toward whichever side has more
    # edges until nothing moves. It minimises the same total edge length,
    # but it can stop at a different rank than network simplex on a graph
    # where moving one node alone does not help.
    class ErDiagramLayering
      MIN_LENGTH = 2
      MAX_PASSES = 100

      # @param ids [Array<String>] entity ids in declaration order
      # @param edges [Array<Array(String, String)>] [source, target] pairs
      # @return [Array(Hash, Array)] each id's rank, and the edges pointing
      #   down the ranks (nil for a self-loop); a cycle is broken by turning
      #   its back edge around
      def self.call(ids, edges)
        new(ids, edges).call
      end

      def initialize(ids, edges)
        @ids = ids
        @edges = edges
      end

      def call
        oriented = acyclic(@edges)
        ranks = longest_path(oriented.compact)
        balance(ranks, oriented.compact)
        floor = ranks.values.min || 0
        [ranks.transform_values { |rank| rank - floor }, oriented]
      end

      private

      # Depth-first, in declaration order: an edge into a node still on the
      # stack closes a cycle and is reversed.
      def acyclic(edges)
        on_stack = {}
        seen = {}
        reversed = {}
        @ids.each { |id| visit(id, edges, on_stack, seen, reversed) }
        edges.each_with_index.map do |(from, to), index|
          next if from == to

          reversed[index] ? [to, from] : [from, to]
        end
      end

      def visit(id, edges, on_stack, seen, reversed)
        return if seen[id]

        seen[id] = on_stack[id] = true
        edges.each_with_index do |(from, to), index|
          next unless from == id && to != id

          reversed[index] = true if on_stack[to]
          visit(to, edges, on_stack, seen, reversed)
        end
        on_stack[id] = false
      end

      def longest_path(edges)
        ranks = @ids.to_h { |id| [id, 0] }
        (@ids.length + 1).times do
          edges.each do |from, to|
            ranks[to] = [ranks[to], ranks[from] + MIN_LENGTH].max
          end
        end
        ranks
      end

      def balance(ranks, edges)
        MAX_PASSES.times do
          moved = @ids.map { |id| relocated?(id, ranks, edges) }
          break unless moved.any?
        end
      end

      def relocated?(id, ranks, edges)
        target = target_rank(id, ranks, edges)
        return false if target.nil? || target == ranks[id]

        ranks[id] = target
        true
      end

      # A node follows whichever side has more edges; equal sides stay put.
      def target_rank(id, ranks, edges)
        incoming, outgoing = sides(id, edges)
        case incoming.length <=> outgoing.length
        when 1 then incoming.map { |from| ranks[from] + MIN_LENGTH }.max
        when -1 then outgoing.map { |to| ranks[to] - MIN_LENGTH }.min
        end
      end

      def sides(id, edges)
        [edges.select { |_from, to| to == id }.map(&:first),
         edges.select { |from, _to| from == id }.map(&:last)]
      end
    end
  end
end
