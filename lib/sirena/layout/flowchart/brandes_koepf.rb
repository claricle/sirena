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
          @up = Hash.new { |hash, key| hash[key] = [] }
          @down = Hash.new { |hash, key| hash[key] = [] }
          links.each do |upper, lower|
            @up[lower] << upper
            @down[upper] << lower
          end
        end

        def positions
          layouts = %i[up down].product(%i[left right]).map do |vert, horiz|
            [horiz, layout(vert, horiz)]
          end
          balance(align_to_narrowest(layouts))
        end

        private

        def layout(vert, horiz)
          layering = vert == :up ? @layers : @layers.reverse
          layering = layering.map(&:reverse) if horiz == :right
          roots = align_blocks(layering, vert == :up ? @up : @down)
          xs = compact(layering, roots)
          horiz == :right ? xs.transform_values(&:-@) : xs
        end

        def align_blocks(layering, neighbours)
          root = {}
          pos = {}
          layering.each do |layer|
            layer.each_with_index do |node, index|
              root[node] = node
              pos[node] = index
            end
          end
          align = root.dup
          layering.each do |layer|
            align_layer(layer, neighbours, root, align, pos)
          end
          root
        end

        def align_layer(layer, neighbours, root, align, pos)
          taken = -1
          layer.each do |node|
            above = neighbours[node].sort_by { |other| pos[other] }
            medians(above).each do |other|
              next unless align[node] == node && taken < pos[other]

              align[other] = node
              align[node] = root[node] = root[other]
              taken = pos[other]
            end
          end
        end

        def medians(sorted)
          return [] if sorted.empty?

          mid = (sorted.size - 1) / 2.0
          sorted.values_at(mid.floor, mid.ceil).uniq
        end

        def compact(layering, root)
          lefts = Hash.new { |hash, key| hash[key] = {} }
          rights = Hash.new { |hash, key| hash[key] = {} }
          layering.each do |layer|
            layer.each_cons(2) do |near, far|
              gap = separation(near, far)
              kept = lefts[root[far]][root[near]] || 0
              lefts[root[far]][root[near]] = [gap, kept].max
              rights[root[near]][root[far]] = lefts[root[far]][root[near]]
            end
          end
          settled = pack_right(root.values.uniq, rights, pack_left(lefts, root))
          root.transform_values { |block| settled[block] }
        end

        def pack_left(lefts, root)
          memo = {}
          visit = lambda do |block|
            memo[block] ||= lefts[block].map { |near, gap|
              visit.call(near) + gap
            }.push(0).max
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
            delta = horiz == :left ? low - xs.values.min : high - xs.values.max
            xs.transform_values { |x| x + delta }
          end
        end

        def extent(xs)
          xs.map { |node, x| x + (@widths[node] / 2.0) }.max -
            xs.map { |node, x| x - (@widths[node] / 2.0) }.min
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
