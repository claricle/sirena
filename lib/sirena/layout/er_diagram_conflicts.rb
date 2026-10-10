# frozen_string_literal: true

module Sirena
  module Layout
    # Finds the edges Brandes-Koepf must not align: a long edge's inner
    # segment crossed by a short one keeps the long edge straight.
    class ErDiagramConflicts
      # @param layers [Array<Array<String>>] ids per rank, left to right
      # @param adjacency [ErDiagramAdjacency]
      # @param dummies [Hash{String=>Boolean}] true for edge-dummy nodes
      # @return [Hash{Array(String, String)=>true}] both orders of each pair
      def self.call(layers, adjacency, dummies)
        new(layers, adjacency, dummies).call
      end

      def initialize(layers, adjacency, dummies)
        @layers = layers
        @predecessors = adjacency.predecessors
        @dummies = dummies
        @order = {}
        layers.each do |layer|
          layer.each_with_index { |id, index| @order[id] = index }
        end
      end

      def call
        @layers.each_cons(2).with_object({}) do |(previous, layer), found|
          scan_layer(previous, layer, found)
        end
      end

      private

      def scan_layer(previous, layer, found)
        left = 0
        scanned = 0
        layer.each_with_index do |id, index|
          other = inner_neighbour(id)
          right = other ? @order[other] : previous.length
          next unless other || id == layer.last

          layer[scanned..index].each { |node| mark(node, left, right, found) }
          scanned = index + 1
          left = right
        end
      end

      def mark(node, left, right, found)
        @predecessors[node].each do |upper|
          next unless crossing?(upper, node, left, right)

          found[[upper, node]] = true
          found[[node, upper]] = true
        end
      end

      def crossing?(upper, node, left, right)
        position = @order[upper]
        (position < left || right < position) &&
          !(@dummies[upper] && @dummies[node])
      end

      def inner_neighbour(id)
        return unless @dummies[id]

        @predecessors[id].find { |upper| @dummies[upper] }
      end
    end
  end
end
