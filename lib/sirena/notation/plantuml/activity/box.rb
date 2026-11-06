# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Activity
        # Where a node sits: its centre and size.
        class Box
          attr_accessor :cx, :cy, :width, :height
          # @return [Float, nil] where arrows meet a bar that has one
          #   neighbour on a side; nil elsewhere
          attr_writer :anchor
          # @return [Array<Box>] the boxes a bar fans out to or gathers
          attr_accessor :fan

          # @return [Float] where a lone neighbour's arrow meets the box
          def anchor
            @anchor || cx
          end

          def initialize(width:, height:)
            @width = width
            @height = height
            @cx = 0.0
            @cy = 0.0
          end

          # @return [Box] the box with these edges
          def self.spanning(left, top, right, bottom)
            new(width: right - left, height: bottom - top).tap do |box|
              box.cx = (left + right) / 2.0
              box.cy = (top + bottom) / 2.0
            end
          end

          # @return [Boolean] whether the vertical through x runs through the box
          def spans?(x_pos)
            left < x_pos && x_pos < right
          end

          def left
            cx - (width / 2.0)
          end

          def right
            cx + (width / 2.0)
          end

          def top
            cy - (height / 2.0)
          end

          def bottom
            cy + (height / 2.0)
          end
        end
      end
    end
  end
end
