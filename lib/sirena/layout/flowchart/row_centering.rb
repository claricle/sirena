# frozen_string_literal: true

require_relative "brandes_koepf"
require_relative "edge_chains"
require_relative "layer_spacing"

module Sirena
  module Layout
    class Flowchart < Base
      # Centres every layer of a laid-out level on one axis, the way dagre
      # leaves a chain of different-sized nodes straight. elkrb sets each
      # layer against the left edge. Works on a level laid out downward.
      #
      # A level whose edges all join neighbouring layers is placed the way
      # dagre does it, with Brandes-Koepf alignment over the layers elkrb
      # chose. An edge's label is as wide as its stand-in there. A level
      # with an unlabelled edge that skips a row or points back up is laid
      # over dagre's layering of it instead, from EdgeChains.
      class RowCentering
        # @param flat [Hash] a level whose boxes elkrb has placed
        # @param label_axis [Symbol, nil] a label's size along the flow,
        #   :height, or :width for a turned level, as for LayerSpacing.
        #   Without it a level with a labelled edge is only centred.
        def self.apply(flat, label_axis: nil)
          new(flat, label_axis).apply
        end

        def initialize(flat, label_axis)
          @flat = flat
          @label_axis = label_axis
        end

        def apply
          rows = @flat[:children].group_by { |box| box[:y] }
          joined = joins(rows)
          return aligned(rows, joined) if joined

          chained_rows = chains(rows)
          return chained(rows, chained_rows) if chained_rows

          centre_rows(rows)
        end

        private

        # The [upper, lower] box of every edge, or nil when the level has
        # an edge that dagre would lay out differently.
        def joins(rows)
          ranks = rank_of(rows)
          pairs = []
          (@flat[:edges] || []).each do |edge|
            pair = joined_ends(edge, ranks)
            return unless pair

            pairs << pair
          end
          pairs unless pairs.empty?
        end

        def joined_ends(edge, ranks)
          return unless @label_axis || edge[:labels].to_a.empty?

          ends = edge_ends(edge)
          ends.reverse! if ranks[ends.first] > ranks[ends.last]
          ends if adjacent?(ends, ranks)
        end

        # The level's dagre layering, or nil when it has no edge, an edge
        # with a label, or an edge within one row.
        def chains(rows)
          ranks = rank_of(rows)
          ends = chain_endpoints(ranks)
          return unless chainable?(ends)

          EdgeChains.new(ranks, ends, ordered_ids)
        end

        def chain_endpoints(ranks)
          (@flat[:edges] || []).map { |edge| chain_ends(edge, ranks) }
        end

        def chainable?(ends)
          !ends.empty? && ends.none?(&:nil?)
        end

        def ordered_ids
          @flat[:children].sort_by { |box| [box[:x], box[:y]] }
            .map { |box| box[:id] }
        end

        # [upper, lower, turned] for an edge that can be chained.
        def chain_ends(edge, ranks)
          return unless edge[:labels].to_a.empty?

          upper, lower = edge_ends(edge)
          return if ranks[upper] == ranks[lower]

          turned = ranks[upper] > ranks[lower]
          turned ? [lower, upper, true] : [upper, lower, false]
        end

        def edge_ends(edge)
          [edge[:sources].first, edge[:targets].first]
        end

        def adjacent?(ends, ranks)
          ranks[ends.last] - ranks[ends.first] == 1
        end

        def rank_of(rows)
          ranked = {}
          rows.keys.sort.each_with_index do |y, rank|
            rows[y].each { |box| ranked[box[:id]] = rank }
          end
          ranked
        end

        def aligned(rows, joins)
          ordered = rows.sort.map { |_, row| row.sort_by { |box| box[:x] } }
          layers, links, dummies = layered(ordered, joins)
          widths = node_widths(ordered, dummies)
          centres = BrandesKoepf.positions(layers, widths, links, dummies)
          place(ordered.flatten, centres)
          @flat
        end

        def chained(rows, chains)
          widths = chain_widths(chains)
          centres = BrandesKoepf.positions(chains.layers, widths,
                                           chains.links, chains.dummies)
          place_chained_rows(rows, chains, centres)
        end

        def chain_widths(chains)
          widths = @flat[:children].to_h { |box| [box[:id], box[:width]] }
          chains.dummies.each { |dummy| widths[dummy] = 0.0 }
          widths
        end

        def place_chained_rows(rows, chains, centres)
          tops = rows.keys.sort
          @flat[:children].each { |box| box[:y] = tops[chains.ranks[box[:id]]] }
          place(@flat[:children], centres)
          @flat
        end

        def centre_rows(rows)
          widest = rows.values.map { |row| span(row) }.max
          rows.each_value { |row| centre(row, widest) }
          @flat
        end

        def node_widths(ordered, dummies)
          widths = ordered.flatten.to_h { |box| [box[:id], box[:width]] }
          dummies.each { |dummy| widths[dummy] = standin_width(dummy) }
          widths
        end

        # The stand-in for the kth edge spans its widest label across the
        # flow: the label's width, or its line box on a turned level.
        def standin_width(dummy)
          labels = @flat[:edges][dummy.last][:labels].to_a
          labels.map { |label| across(label) }.max.to_f
        end

        def across(label)
          return label[:width].to_f if @label_axis == :height

          label[:height].to_f * LayerSpacing::LINE_HEIGHT
        end

        # Rows alternate with a layer of edge stand-ins, as in dagre. Each
        # layer orders them by the lower box first, which is the order
        # dagre's crossing reduction leaves a fan in.
        def layered(ordered, joins)
          slot = {}
          ordered.each { |row| row.each_with_index { |b, i| slot[b[:id]] = i } }
          stand = joins.each_with_index.sort_by do |(upper, lower), _|
            [slot[lower], slot[upper]]
          end
          [stack(ordered, stand), links(stand), stand.map { |_, k| [:edge, k] }]
        end

        def stack(ordered, stand)
          ordered.flat_map.with_index do |row, rank|
            ids = row.map { |box| box[:id] }
            rank == ordered.size - 1 ? [ids] : [ids, standins(stand, ids)]
          end
        end

        def links(stand)
          stand.flat_map do |(up, low), k|
            [[up, [:edge, k]], [[:edge, k], low]]
          end
        end

        def standins(stand, ids)
          stand.select { |(upper, _), _| ids.include?(upper) }
            .map { |_, k| [:edge, k] }
        end

        def place(boxes, centres)
          left = boxes.map { |box| left_edge(box, centres) }.min
          boxes.each do |box|
            box[:x] = left_edge(box, centres) - left
          end
        end

        def left_edge(box, centres)
          centres[box[:id]] - (box[:width] / 2.0)
        end

        def centre(row, widest)
          shift = (widest - span(row)) / 2.0
          row.each { |box| box[:x] += shift }
        end

        def span(row)
          left = row.map { |box| box[:x] }.min
          row.map { |box| box[:x] + box[:width] }.max - left
        end
      end
    end
  end
end
