# frozen_string_literal: true

module Sirena
  module Layout
    class Flowchart < Base
      # Stretches a subgraph across the boxes that have an edge into it.
      #
      # dagre lays a subgraph out together with the graph around it. An edge
      # from a box beside the subgraph passes through the ranks the subgraph
      # spans, and the subgraph's borders keep clear of it, so the subgraph
      # grows along the rank to cover where the edge comes from. Works on a
      # level whose boxes are already placed.
      class ClusterReach
        # Distance from the centre of a box with an edge into the subgraph to
        # the subgraph's border on that side, as dagre leaves it.
        REACH = 46.0

        # @param boxes [Array<Hash>] the placed boxes of one level
        # @param level_edges [Array] [edge, source box id, target box id]
        #   triples laid out at that level
        # @param sideways [Boolean] whether ranks run left to right
        def self.apply(boxes, level_edges, sideways:)
          new(boxes, sideways).apply(level_edges)
        end

        def initialize(boxes, sideways)
          @boxes = boxes
          @position, @size = sideways ? %i[y height] : %i[x width]
          @by_id = {}
          boxes.each { |box| @by_id[box[:id]] ||= box }
        end

        def apply(level_edges)
          wanted = Hash.new { |hash, key| hash[key] = [] }
          level_edges.each do |(_edge, from, to)|
            reach(wanted, @by_id[from], @by_id[to])
            reach(wanted, @by_id[to], @by_id[from])
          end
          wanted.each { |cluster, centres| stretch(cluster, centres) }
        end

        private

        def reach(wanted, cluster, other)
          return unless cluster && other && !cluster.equal?(other)
          return unless cluster.dig(:metadata, :cluster) == true

          wanted[cluster] << other[@position] + (other[@size] / 2.0)
        end

        def stretch(cluster, centres)
          low = [cluster[@position], centres.min - REACH].min
          high = [cluster[@position] + cluster[@size], centres.max + REACH].max
          before = cluster[@position]
          return if low == before && high == before + cluster[@size]

          resize(cluster, low, high)
        end

        # The contents stay where they are on the page.
        def resize(cluster, low, high)
          grown = cluster[@position] - low
          cluster[@position] = low
          cluster[@size] = high - low
          (cluster[:children] || []).each { |child| child[@position] += grown }
        end
      end
    end
  end
end
