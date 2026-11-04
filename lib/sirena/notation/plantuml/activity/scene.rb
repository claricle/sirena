# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Activity
        # A laid-out activity diagram: its size and its marks back to front.
        class Scene
          attr_reader :width, :height, :marks

          def initialize(width:, height:, marks:)
            @width = width
            @height = height
            @marks = marks
          end
        end
      end
    end
  end
end
