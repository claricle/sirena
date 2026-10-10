# frozen_string_literal: true

module Sirena
  module Layout
    # Orders the nodes within each rank to cut edge crossings, following
    # dagre's order step: a depth-first starting order, then alternating
    # barycenter sweeps up and down, keeping the layering with the fewest
    # crossings. Dummy nodes stand in for the middle of every edge.
    class ErDiagramOrdering
      STALL_LIMIT = 4

      # @param ranks [Hash{String=>Integer}] rank of every node, dummies too
      # @param edges [Array<Array(String, String)>] chain edges, rank by rank
      # @return [Array<Array<String>>] the ids on each rank, left to right
      def self.call(ranks, edges)
        new(ranks, edges).call
      end

      def initialize(ranks, edges)
        @ranks = ranks
        @successors = Hash.new { |hash, key| hash[key] = [] }
        @predecessors = Hash.new { |hash, key| hash[key] = [] }
        edges.each do |from, to|
          @successors[from] << to
          @predecessors[to] << from
        end
      end

      def call
        layers = starting_layers
        best = nil
        best_crossings = Float::INFINITY
        stalled = 0
        sweep = 0
        while stalled < STALL_LIMIT
          layers = sweep_once(layers, sweep)
          crossings = crossing_count(layers)
          if crossings < best_crossings
            best = layers.map(&:dup)
            best_crossings = crossings
            stalled = 0
          end
          stalled += 1
          sweep += 1
        end
        best
      end

      private

      def starting_layers
        layers = Array.new((@ranks.values.max || -1) + 1) { [] }
        seen = {}
        @ranks.keys.sort_by.with_index { |id, index| [@ranks[id], index] }
          .each { |id| descend(id, layers, seen) }
        layers
      end

      def descend(id, layers, seen)
        return if seen[id]

        seen[id] = true
        layers[@ranks[id]] << id
        @successors[id].each { |to| descend(to, layers, seen) }
      end

      def sweep_once(layers, sweep)
        layers = layers.map(&:dup)
        bias_right = (sweep % 4) >= 2
        if sweep.odd?
          (1...layers.length).each do |rank|
            layers[rank] = reorder(layers[rank], layers[rank - 1],
                                   @predecessors, bias_right)
          end
        else
          (layers.length - 2).downto(0) do |rank|
            layers[rank] = reorder(layers[rank], layers[rank + 1],
                                   @successors, bias_right)
          end
        end
        layers
      end

      # A node with no neighbour in the fixed layer keeps its slot.
      def reorder(layer, fixed, neighbours, bias_right)
        position = fixed.each_with_index.to_h
        entries = layer.each_with_index.map do |id, index|
          near = neighbours[id].filter_map { |other| position[other] }
          { id: id, index: index,
            barycenter: near.empty? ? nil : near.sum.fdiv(near.length) }
        end
        merge(entries.reject { |entry| entry[:barycenter].nil? }, entries
          .select { |entry| entry[:barycenter].nil? }, bias_right)
      end

      def merge(sortable, unsortable, bias_right)
        sortable = sortable.sort do |a, b|
          compare = a[:barycenter] <=> b[:barycenter]
          next compare unless compare.zero?

          bias_right ? b[:index] - a[:index] : a[:index] - b[:index]
        end
        pending = unsortable.sort_by { |entry| -entry[:index] }
        ordered = []
        take_pending(ordered, pending)
        sortable.each do |entry|
          ordered << entry[:id]
          take_pending(ordered, pending)
        end
        ordered
      end

      def take_pending(ordered, pending)
        while pending.any? && pending.last[:index] <= ordered.length
          ordered << pending.pop[:id]
        end
      end

      def crossing_count(layers)
        layers.each_cons(2).sum do |upper, lower|
          crossings_between(upper, lower)
        end
      end

      def crossings_between(upper, lower)
        position = lower.each_with_index.to_h
        pairs = upper.flat_map do |id|
          @successors[id].filter_map { |to| position[to] }.sort
        end
        pairs.each_with_index.sum do |value, index|
          pairs[(index + 1)..].count { |later| later < value }
        end
      end
    end
  end
end
