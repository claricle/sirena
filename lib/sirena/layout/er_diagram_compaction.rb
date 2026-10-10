# frozen_string_literal: true

module Sirena
  module Layout
    # Gives each block of aligned nodes its x: blocks keep their rank order
    # and at least the separation apart, pushed left first and then back
    # right as far as their neighbours allow.
    class ErDiagramCompaction
      # @param layers [Array<Array<String>>] ids per rank, in sweep order
      # @param root [Hash{String=>String}] the block root of every node
      # @param separation [#call] (left_id, right_id) => minimum distance
      def initialize(layers, root, separation)
        @layers = layers
        @root = root
        @separation = separation
      end

      # @return [Hash{String=>Numeric}] x of every node
      def call
        build_graph
        positions = place_blocks
        @root.transform_values { |block| positions[block] }
      end

      private

      def build_graph
        @incoming = Hash.new { |hash, block| hash[block] = {} }
        @outgoing = Hash.new { |hash, block| hash[block] = {} }
        @layers.each { |layer| add_layer(layer) }
      end

      def add_layer(layer)
        layer.each_cons(2) { |left, right| link(left, right) }
        layer.each { |id| declare(@root[id]) }
      end

      # Looking a block up adds it to both graphs, so blocks with no
      # neighbour in their rank still get placed.
      def declare(block)
        [@incoming, @outgoing].each { |graph| graph[block] }
      end

      def link(left, right)
        from = @root[left]
        to = @root[right]
        gap = [@separation.call(left, right), @incoming[to][from] || 0].max
        @incoming[to][from] = gap
        @outgoing[from][to] = gap
      end

      def place_blocks
        positions = {}
        visit(@incoming) { |block| push_right(block, positions) }
        visit(@outgoing) { |block| pull_back(block, positions) }
        positions
      end

      def push_right(block, positions)
        farthest = @incoming[block].map { |from, gap| positions[from] + gap }
        positions[block] = farthest.max || 0
      end

      def pull_back(block, positions)
        least = @outgoing[block].map { |to, gap| positions[to] - gap }.min
        positions[block] = [positions[block], least].max if least
      end

      # Yields every key after the keys it points at.
      def visit(graph)
        done = Set.new
        graph.each_key do |start|
          stack = [[start, false]]
          until stack.empty?
            id, expanded = stack.pop
            next yield(id) if expanded
            next unless done.add?(id)

            stack.push([id, true], *graph.fetch(id).keys.map { |o| [o, false] })
          end
        end
      end
    end
  end
end
