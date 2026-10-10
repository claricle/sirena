# frozen_string_literal: true

require_relative "er_diagram_adjacency"
require_relative "er_diagram_conflicts"
require_relative "er_diagram_alignment"
require_relative "er_diagram_compaction"

module Sirena
  module Layout
    # Assigns each node its x by Brandes-Koepf, as dagre does: four
    # alignments (up/down, left/right) are compacted, aligned to the
    # narrowest, and each node takes the mean of its two middle values.
    class ErDiagramCoordinates
      ALIGNMENTS = %i[up down].product(%i[left right]).freeze

      # @param layers [Array<Array<String>>] ids per rank, left to right
      # @param edges [Array<Array(String, String)>] chain edges
      # @param widths [Hash{String=>Numeric}] node widths
      # @param dummies [Hash{String=>Boolean}] true for edge-dummy nodes
      # @param spacing [Hash] :node and :edge separation
      # @return [Hash{String=>Float}] centre x of every node
      def self.call(layers, edges, widths, dummies, spacing)
        new(layers, edges, widths, dummies, spacing).call
      end

      def initialize(layers, edges, widths, dummies, spacing)
        @layers = layers
        @widths = widths
        @dummies = dummies
        @spacing = spacing
        @adjacency = ErDiagramAdjacency.new(edges)
        @conflicts = ErDiagramConflicts.call(layers, @adjacency, dummies)
      end

      def call
        by_alignment = ALIGNMENTS.to_h do |vertical, horizontal|
          [[vertical, horizontal], alignment(vertical, horizontal)]
        end
        narrowest = by_alignment.values.min_by { |xs| extent(xs) }
        shift_to(by_alignment, narrowest)
        balance(by_alignment)
      end

      private

      def alignment(vertical, horizontal)
        layers = sweep_order(vertical, horizontal)
        neighbours = if vertical == :up
                       @adjacency.predecessors
                     else
                       @adjacency.successors
                     end
        root = ErDiagramAlignment.new(neighbours, @conflicts).call(layers)
        xs = ErDiagramCompaction.new(layers, root, method(:separation)).call
        horizontal == :right ? xs.transform_values(&:-@) : xs
      end

      def sweep_order(vertical, horizontal)
        layers = vertical == :up ? @layers : @layers.reverse
        horizontal == :right ? layers.map(&:reverse) : layers
      end

      def separation(left, right)
        (@widths[left] / 2.0) + margin(left) + margin(right) +
          (@widths[right] / 2.0)
      end

      def margin(id)
        (@dummies[id] ? @spacing[:edge] : @spacing[:node]) / 2.0
      end

      def extent(positions)
        sides = positions.flat_map do |id, x|
          [x - (@widths[id] / 2.0), x + (@widths[id] / 2.0)]
        end
        sides.max - sides.min
      end

      def shift_to(by_alignment, narrowest)
        bounds = narrowest.values.minmax
        by_alignment.each do |key, positions|
          next if positions.equal?(narrowest)

          delta = offset(positions, key.last, bounds)
          by_alignment[key] = positions.transform_values { |x| x + delta }
        end
      end

      def offset(positions, horizontal, bounds)
        low, high = bounds
        return low - positions.values.min if horizontal == :left

        high - positions.values.max
      end

      def balance(by_alignment)
        by_alignment[ALIGNMENTS.first].keys.to_h do |id|
          middle = ALIGNMENTS.map { |key| by_alignment[key][id] }.sort
          [id, (middle[1] + middle[2]) / 2.0]
        end
      end
    end
  end
end
