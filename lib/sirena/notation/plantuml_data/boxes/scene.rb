# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUMLData
      module Boxes
        # The laid-out diagram: canvas size and its marks, back to front.
        # A mark is a Hash with a `:kind` of :rect, :line, :text, :path,
        # :polygon or :circle and the attributes of that SVG element.
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
end
