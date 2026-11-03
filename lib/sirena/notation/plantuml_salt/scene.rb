# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUMLSalt
      # The laid-out diagram: canvas size and its marks, back to front.
      class Scene
        attr_reader :width, :height, :marks

        def initialize(width:, height:, marks:)
          @width = width
          @height = height
          @marks = marks.freeze
          freeze
        end

        def view_box
          "0 0 #{width} #{height}"
        end
      end
    end
  end
end
