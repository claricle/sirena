# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module NodeGraph
        # What one scope's layout came to: where each item sits inside the
        # scope and how big the scope is.
        Packed = Struct.new(:offsets, :width, :height, keyword_init: true)

        # Stacks the items of each rank along the cross axis and the ranks
        # along the main axis.
        class Packer
          MAIN_GAP = 70.0
          CROSS_GAP = 28.0
          REACH_SHARE = 0.8

          # @param sizes [Hash{Object => Array(Float, Float)}] width, height
          # @param left_to_right [Boolean] whether ranks run left to right
          # @param reach [Hash{Object => Float}] the widest label on a link of
          #   each item; side by side items stay half of both apart
          def initialize(sizes, left_to_right:, reach: {})
            @sizes = sizes
            @reach = left_to_right ? {} : reach
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
            layer.map { |item| @sizes[item][@main] }.max || 0.0
          end

          def cross_extent(layer)
            return 0.0 if layer.empty?

            layer.sum { |item| @sizes[item][@cross] } +
              layer.each_cons(2).sum { |pair| gap(*pair) }
          end

          # Centres of two neighbours sit a share of both labels' reach apart.
          def gap(first, second)
            reach = [first, second].sum { |item| @reach[item].to_f } / 2
            half = [first, second].sum { |item| @sizes[item][@cross] } / 2
            [CROSS_GAP, (REACH_SHARE * reach) - half].max
          end

          def stack(layer, main, cross, offsets)
            layer.each_with_index do |item, index|
              offset = [0.0, 0.0]
              offset[@main] = main
              offset[@cross] = cross
              offsets[item] = offset
              cross += @sizes[item][@cross] +
                (layer[index + 1] ? gap(item, layer[index + 1]) : 0.0)
            end
          end
        end
      end
    end
  end
end
