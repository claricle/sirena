# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUMLSalt
      # A rectangle in canvas units: where it starts and how big it is.
      class Box
        attr_reader :left, :top, :width, :height

        def initialize(left, top, width, height)
          @left = left
          @top = top
          @width = width
          @height = height
          freeze
        end

        # @return [Float] the x of the right edge
        def right
          left + width
        end

        # @return [Float] the y of the bottom edge
        def bottom
          top + height
        end
      end
    end
  end
end
