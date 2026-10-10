# frozen_string_literal: true

require_relative "er_diagram_adjacency"

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
        adjacency = ErDiagramAdjacency.new(edges)
        @successors = adjacency.successors
        @predecessors = adjacency.predecessors
      end

      def call
        layers = starting_layers
        best = nil
        stalled = 0
        0.step do |sweep|
          layers = sweep_once(layers, sweep)
          best, stalled = better(best, layers, stalled)
          return best.first if stalled >= STALL_LIMIT
        end
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

      # @param best [Array(Array, Integer), nil] layers and their crossings
      # @return [Array(Array, Integer)] the fewer-crossings candidate, and
      #   how many sweeps in a row it has stood
      def better(best, layers, stalled)
        crossings = crossing_count(layers)
        return [best, stalled + 1] if best && best.last <= crossings

        [[layers, crossings], 1]
      end

      def sweep_once(layers, sweep)
        layers = layers.dup
        order, offset, neighbours = sweep_plan(layers.length, sweep.odd?)
        order.each do |rank|
          layers[rank] = reorder(layers[rank], layers[rank + offset],
                                 neighbours, (sweep % 4) >= 2)
        end
        layers
      end

      # The ranks to visit, where the fixed rank lies relative to each, and
      # which edges say where a node belongs.
      def sweep_plan(count, downwards)
        if downwards
          [(1...count), -1, @predecessors]
        else
          [(count - 2).downto(0), 1, @successors]
        end
      end

      # A node with no neighbour in the fixed layer keeps its slot.
      def reorder(layer, fixed, neighbours, bias_right)
        position = fixed.each_with_index.to_h
        centres = layer.to_h { |id| [id, barycenter(neighbours[id], position)] }
        movable, keepers =
          layer.each_with_index.partition { |id, _| centres[id] }
        merge(rank(movable, centres, bias_right), keepers)
      end

      # Ties on the barycenter keep the old order, or reverse it on a
      # right-biased sweep.
      def rank(movable, centres, bias_right)
        movable.sort_by do |id, index|
          [centres[id], bias_right ? -index : index]
        end.map(&:first)
      end

      def barycenter(neighbours, position)
        near = neighbours.filter_map { |other| position[other] }
        near.sum.fdiv(near.length) unless near.empty?
      end

      # Puts each keeper back at its old index once enough nodes precede it.
      def merge(movable, keepers)
        ordered = []
        take_keepers(ordered, keepers)
        movable.each do |id|
          ordered << id
          take_keepers(ordered, keepers)
        end
        ordered
      end

      def take_keepers(ordered, keepers)
        while keepers.any? && keepers.first.last <= ordered.length
          ordered << keepers.shift.first
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
