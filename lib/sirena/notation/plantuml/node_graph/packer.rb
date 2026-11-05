# frozen_string_literal: true

require_relative "skipped_ranks"

module Sirena
  module Notation
    module PlantUML
      module NodeGraph
        # What one scope's layout came to: where each item sits inside the
        # scope and how big the scope is. `paths` holds, for a link across
        # ranks, the points it passes through in the ranks it skips.
        Packed = Struct.new(:offsets, :width, :height, :paths,
                            keyword_init: true)

        # Stacks the items of each rank along the cross axis and the ranks
        # along the main axis.
        class Packer
          MAIN_GAP = 70.0
          CROSS_GAP = 28.0
          # The room between a skipped link and what stands beside it.
          WAYPOINT_GAP = 17.0

          # @param sizes [Hash{Object => Array(Float, Float)}] width, height
          # @param left_to_right [Boolean] whether ranks run left to right
          def initialize(sizes, left_to_right:)
            @sizes = sizes
            @main = left_to_right ? 0 : 1
            @cross = 1 - @main
          end

          # @param layers [Array<Array<Object>>]
          # @return [Packed]
          def pack(layers)
            extents = layers.map { |layer| cross_extent(layer) }
            widest = extents.max || 0.0
            offsets = {}
            margins = extents.map { |extent| (widest - extent) / 2 }
            packed(offsets, lay_out(layers, margins, offsets), widest)
          end

          # @param packed [Packed]
          # @param chains [Hash{Array => Array<Waypoint>}]
          # @return [Packed] `packed` with the point of each chain, and
          #   without the waypoints among its offsets
          def route(packed, chains)
            packed.paths = chains.transform_values do |waypoints|
              waypoints.map { |waypoint| packed.offsets.fetch(waypoint) }
            end
            packed.offsets.delete_if { |item, _| item.is_a?(Waypoint) }
            packed
          end

          private

          def lay_out(layers, margins, offsets)
            at = 0.0
            layers.zip(margins) do |layer, margin|
              stack(layer, at, margin, offsets)
              at += main_extent(layer) + MAIN_GAP
            end
            layers.empty? ? 0.0 : at - MAIN_GAP
          end

          def packed(offsets, main, cross)
            size = [0.0, 0.0]
            size[@main] = main
            size[@cross] = cross
            Packed.new(offsets: offsets, width: size[0], height: size[1])
          end

          def main_extent(layer)
            layer.map { |item| size(item)[@main] }.max || 0.0
          end

          def cross_extent(layer)
            return 0.0 if layer.empty?

            layer.sum { |item| size(item)[@cross] } + gaps(layer).sum
          end

          # Waypoints have no size.
          def size(item)
            item.is_a?(Waypoint) ? [0.0, 0.0] : @sizes[item]
          end

          def gaps(layer)
            layer.each_cons(2).map do |before, after|
              [before, after].any?(Waypoint) ? WAYPOINT_GAP : CROSS_GAP
            end
          end

          # A waypoint's offset is the point itself, in the middle of the
          # rank.
          def stack(layer, main, cross, offsets)
            middle = main + (main_extent(layer) / 2)
            layer.zip([0.0, *gaps(layer)]).each do |item, gap|
              cross += gap
              offsets[item] = offset(item.is_a?(Waypoint) ? middle : main,
                                     cross)
              cross += size(item)[@cross]
            end
          end

          def offset(main, cross)
            [0.0, 0.0].tap do |point|
              point[@main] = main
              point[@cross] = cross
            end
          end
        end
      end
    end
  end
end
