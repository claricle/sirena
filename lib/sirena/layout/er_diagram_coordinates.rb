# frozen_string_literal: true

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
        @successors = Hash.new { |hash, key| hash[key] = [] }
        @predecessors = Hash.new { |hash, key| hash[key] = [] }
        edges.each do |from, to|
          @successors[from] << to
          @predecessors[to] << from
        end
        @order = {}
        layers.each { |layer| layer.each_with_index { |id, i| @order[id] = i } }
        @conflicts = type1_conflicts
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
        layers = vertical == :up ? @layers : @layers.reverse
        layers = layers.map(&:reverse) if horizontal == :right
        neighbours = vertical == :up ? @predecessors : @successors
        root, align = vertical_alignment(layers, neighbours)
        xs = compact(layers, root, align)
        horizontal == :right ? xs.transform_values(&:-@) : xs
      end

      # Marks edges that must not be aligned: a long edge's inner segment
      # crossed by a short one keeps the long edge straight.
      def type1_conflicts
        conflicts = {}
        @layers.each_cons(2) do |previous, layer|
          scan_layer(previous, layer, conflicts)
        end
        conflicts
      end

      def scan_layer(previous, layer, conflicts)
        left = 0
        scanned = 0
        layer.each_with_index do |id, index|
          other = inner_neighbour(id)
          right = other ? @order[other] : previous.length
          next unless other || id == layer.last

          layer[scanned..index].each do |node|
            mark_conflicts(node, left, right, conflicts)
          end
          scanned = index + 1
          left = right
        end
      end

      def mark_conflicts(node, left, right, conflicts)
        @predecessors[node].each do |upper|
          position = @order[upper]
          crossing = position < left || right < position
          next unless crossing && !(@dummies[upper] && @dummies[node])

          conflicts[[upper, node]] = true
          conflicts[[node, upper]] = true
        end
      end

      def inner_neighbour(id)
        return unless @dummies[id]

        @predecessors[id].find { |upper| @dummies[upper] }
      end

      def vertical_alignment(layers, neighbours)
        root = {}
        align = {}
        position = {}
        layers.each do |layer|
          layer.each_with_index do |id, index|
            root[id] = align[id] = id
            position[id] = index
          end
          align_layer(layer, neighbours, position, root, align)
        end
        [root, align]
      end

      def align_layer(layer, neighbours, position, root, align)
        previous = -1
        layer.each do |id|
          candidates = neighbours[id].sort_by { |other| position[other] }
          next if candidates.empty?

          middle = (candidates.length - 1) / 2.0
          (middle.floor..middle.ceil).each do |index|
            other = candidates[index]
            next unless align[id] == id && previous < position[other] &&
                        !@conflicts[[id, other]]

            align[other] = id
            align[id] = root[id] = root[other]
            previous = position[other]
          end
        end
      end

      def compact(layers, root, align)
        blocks = block_graph(layers, root)
        xs = {}
        post_order(blocks[:incoming]) do |id|
          xs[id] = blocks[:incoming][id].map { |from, gap| xs[from] + gap }
            .max || 0
        end
        post_order(blocks[:outgoing]) do |id|
          least = blocks[:outgoing][id].map { |to, gap| xs[to] - gap }.min
          xs[id] = [xs[id], least].max if least
        end
        align.keys.to_h { |id| [id, xs[root[id]]] }
      end

      def block_graph(layers, root)
        incoming = Hash.new { |hash, key| hash[key] = {} }
        outgoing = Hash.new { |hash, key| hash[key] = {} }
        layers.each do |layer|
          layer.each_cons(2) do |left, right|
            from = root[left]
            to = root[right]
            gap = [separation(left, right), incoming[to][from] || 0].max
            incoming[to][from] = gap
            outgoing[from][to] = gap
          end
          layer.each do |id|
            incoming[root[id]]
            outgoing[root[id]]
          end
        end
        { incoming: incoming.transform_values(&:to_a),
          outgoing: outgoing.transform_values(&:to_a) }
      end

      # Yields every key after the keys it points at.
      def post_order(graph)
        done = {}
        graph.each_key do |start|
          stack = [[start, false]]
          until stack.empty?
            id, expanded = stack.pop
            next yield(id) if expanded
            next if done[id]

            done[id] = true
            stack.push([id, true])
            graph[id].map(&:first).each { |other| stack.push([other, false]) }
          end
        end
      end

      def separation(left, right)
        half = ->(id) { (@dummies[id] ? @spacing[:edge] : @spacing[:node]) / 2.0 }
        (@widths[left] / 2.0) + half.call(left) + half.call(right) +
          (@widths[right] / 2.0)
      end

      def extent(xs)
        high = xs.map { |id, x| x + (@widths[id] / 2.0) }.max
        low = xs.map { |id, x| x - (@widths[id] / 2.0) }.min
        high - low
      end

      def shift_to(by_alignment, narrowest)
        low = narrowest.values.min
        high = narrowest.values.max
        by_alignment.each_key do |key|
          xs = by_alignment[key]
          next if xs.equal?(narrowest)

          delta = key.last == :left ? low - xs.values.min : high - xs.values.max
          by_alignment[key] = xs.transform_values { |x| x + delta }
        end
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
