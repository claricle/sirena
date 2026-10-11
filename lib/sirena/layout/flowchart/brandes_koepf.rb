# frozen_string_literal: true

module Sirena
  module Layout
    class Flowchart < Base
      # dagre's horizontal placement: Brandes-Koepf over a layered graph.
      # Each of the four alignments packs blocks of vertically aligned
      # nodes; the result is the mean of the two middle candidates.
      class BrandesKoepf
        NODE_SEP = 50.0
        EDGE_SEP = 20.0

        # @param layers [Array<Array>] node ids, top layer first, in order
        # @param widths [Hash] node id => width
        # @param links [Array<Array>] [upper, lower] pairs on adjacent layers
        # @param dummies [Array] ids that stand for an edge, not a box
        # @return [Hash] node id => centre
        def self.positions(layers, widths, links, dummies)
          new(layers, widths, links, dummies).positions
        end

        def initialize(layers, widths, links, dummies)
          @layers = layers
          @widths = widths
          @dummies = dummies
          @up = index_links(links)
          @down = index_links(links.map(&:reverse))
        end

        def positions
          layouts = %i[up down].product(%i[left right]).map do |vert, horiz|
            [horiz, layout(vert, horiz)]
          end
          balance(align_to_narrowest(layouts))
        end

        private

        def index_links(links)
          index = Hash.new { |hash, key| hash[key] = [] }
          links.each_with_object(index) do |(upper, lower), result|
            result[lower] << upper
          end
        end

        def layout(vert, horiz)
          layering = oriented_layers(vert, horiz)
          roots = align_blocks(layering, neighbours(vert))
          positions = compact(layering, roots)
          horiz == :right ? mirror(positions) : positions
        end

        def oriented_layers(vert, horiz)
          layering = vert == :up ? @layers : @layers.reverse
          horiz == :right ? layering.map(&:reverse) : layering
        end

        def neighbours(vert)
          vert == :up ? @up : @down
        end

        def mirror(positions)
          positions.transform_values(&:-@)
        end

        def align_blocks(layering, neighbours)
          root, pos = layer_indexes(layering)
          align = root.dup
          layering.each do |layer|
            align_layer(layer, neighbours, root, align, pos)
          end
          root
        end

        def layer_indexes(layering)
          root = {}
          pos = {}
          layering.each do |layer|
            layer.each_with_index do |node, index|
              root[node] = node
              pos[node] = index
            end
          end
          [root, pos]
        end

        def align_layer(layer, neighbours, root, align, pos)
          taken = -1
          layer.each do |node|
            above = neighbours[node].sort_by { |other| pos[other] }
            medians(above).each do |other|
              next unless alignable?(node, other, taken, align, pos)

              align_pair(node, other, root, align)
              taken = pos[other]
            end
          end
        end

        def alignable?(node, other, taken, align, pos)
          align[node] == node && taken < pos[other]
        end

        def align_pair(node, other, root, align)
          align[other] = node
          align[node] = root[node] = root[other]
        end

        def medians(sorted)
          return [] if sorted.empty?

          mid = (sorted.size - 1) / 2.0
          sorted.values_at(mid.floor, mid.ceil).uniq
        end

        def compact(layering, root)
          lefts, rights = constraints(layering, root)
          settled = pack_right(root.values.uniq, rights, pack_left(lefts, root))
          root.transform_values { |block| settled[block] }
        end

        def constraints(layering, root)
          lefts = block_graph
          rights = block_graph
          layering.each do |layer|
            layer.each_cons(2) do |near, far|
              constrain(lefts, rights, root, near, far)
            end
          end
          [lefts, rights]
        end

        def block_graph
          Hash.new { |hash, key| hash[key] = {} }
        end

        def constrain(lefts, rights, root, near, far)
          near_block = root[near]
          far_block = root[far]
          kept = lefts[far_block].fetch(near_block, 0)
          gap = [separation(near, far), kept].max
          connect(lefts, far_block, near_block, gap)
          connect(rights, near_block, far_block, gap)
        end

        def connect(graph, from, to, gap)
          graph[from][to] = gap
        end

        def pack_left(lefts, root)
          memo = {}
          visit = lambda do |block|
            memo[block] ||= lefts[block].map do |near, gap|
              visit.call(near) + gap
            end.push(0).max
          end
          root.values.uniq.each { |block| visit.call(block) }
          memo
        end

        def pack_right(blocks, rights, packed)
          memo = {}
          visit = lambda do |block|
            memo[block] ||= begin
              limit = rights[block].map { |far, gap| visit.call(far) - gap }.min
              limit ? [packed[block], limit].max : packed[block]
            end
          end
          blocks.each { |block| visit.call(block) }
          memo
        end

        def separation(near, far)
          half = ->(node) { @widths[node] / 2.0 }
          reach = ->(node) { @dummies.include?(node) ? EDGE_SEP : NODE_SEP }
          half.(near) + half.(far) + ((reach.(near) + reach.(far)) / 2.0)
        end

        def align_to_narrowest(layouts)
          narrowest = layouts.min_by { |_, xs| extent(xs) }.last
          low, high = narrowest.values.minmax
          layouts.map do |horiz, xs|
            align_layout(horiz, xs, low, high)
          end
        end

        def align_layout(horiz, positions, low, high)
          edge = horiz == :left ? positions.values.min : positions.values.max
          target = horiz == :left ? low : high
          delta = target - edge
          positions.transform_values { |position| position + delta }
        end

        def extent(positions)
          positions.map { |node, x| x + (@widths[node] / 2.0) }.max -
            positions.map { |node, x| x - (@widths[node] / 2.0) }.min
        end

        def balance(candidates)
          candidates.first.keys.to_h do |node|
            middle = candidates.map { |xs| xs[node] }.sort[1, 2]
            [node, middle.sum / 2.0]
          end
        end
      end
    end
  end
end
