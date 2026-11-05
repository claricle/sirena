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
              (CROSS_GAP * (layer.size - 1))
          end

          def stack(layer, main, cross, offsets)
            layer.each do |item|
              offset = [0.0, 0.0]
              offset[@main] = main
              offset[@cross] = cross
              offsets[item] = offset
              cross += @sizes[item][@cross] + CROSS_GAP
            end
          end
        end
      end
    end
  end
end
