# frozen_string_literal: true

module Sirena
  module Layout
    # One vertical alignment of Brandes-Koepf: each node joins the block of
    # its median neighbour in the rank before, unless that would cross
    # another alignment or use a conflicted edge.
    class ErDiagramAlignment
      # @param neighbours [Hash{String=>Array<String>}] the ids in the
      #   previous rank that each node may join
      # @param conflicts [Hash] pairs that must not be joined
      def initialize(neighbours, conflicts)
        @neighbours = neighbours
        @conflicts = conflicts
      end

      # @param layers [Array<Array<String>>] ids per rank, in sweep order
      # @return [Hash{String=>String}] the block root of every node
      def call(layers)
        @root = {}
        @align = {}
        @position = {}
        layers.each do |layer|
          register(layer)
          align_layer(layer)
        end
        @root
      end

      private

      def register(layer)
        layer.each_with_index do |id, index|
          @root[id] = @align[id] = id
          @position[id] = index
        end
      end

      def align_layer(layer)
        previous = -1
        layer.each do |id|
          candidates = @neighbours[id].sort_by { |other| @position[other] }
          previous = join_median(id, candidates, previous)
        end
      end

      def join_median(id, candidates, previous)
        return previous if candidates.empty?

        middle = (candidates.length - 1) / 2.0
        (middle.floor..middle.ceil).each do |index|
          other = candidates[index]
          next unless joinable?(id, other, previous)

          join(id, other)
          previous = @position[other]
        end
        previous
      end

      def joinable?(id, other, previous)
        @align[id] == id && previous < @position[other] &&
          !@conflicts[[id, other]]
      end

      def join(id, other)
        @align[other] = id
        @align[id] = @root[id] = @root[other]
      end
    end
  end
end
