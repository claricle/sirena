# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Drawing
        # A rectangle's left, top, width and height.
        Box = Struct.new(:left, :top, :width, :height) do
          def right
            left + width
          end

          def bottom
            top + height
          end

          def centre
            left + (width / 2)
          end

          def middle
            top + (height / 2)
          end
        end
      end
    end
  end
end
