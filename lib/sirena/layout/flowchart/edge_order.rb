# frozen_string_literal: true

module Sirena
  module Layout
    class Flowchart < Base
      # Puts the boxes that have an edge in the order their edges list
      # them, in the slots those boxes already hold. dagre orders a layer
      # by its edges; elkrb keeps the order the boxes are given in, so a
      # fan reads the same way only when the boxes arrive in edge order.
      module EdgeOrder
        # @param flat [Hash] a level whose boxes are still unplaced
        # @return [Hash] the same level, its children reordered
        def self.apply(flat)
          rank = ranks(flat[:edges] || [])
          flat[:children] = refill(flat[:children], rank)
          flat
        end

        def self.refill(boxes, rank)
          linked = boxes.select { |box| rank.key?(box[:id]) }
            .sort_by { |box| rank.fetch(box[:id]) }.each
          boxes.map { |box| rank.key?(box[:id]) ? linked.next : box }
        end
        private_class_method :refill

        def self.ranks(edges)
          edges.flat_map { |edge| [edge[:sources].first, edge[:targets].first] }
            .uniq.each_with_index.to_h
        end
        private_class_method :ranks
      end
    end
  end
end
