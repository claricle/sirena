# frozen_string_literal: true

require_relative "../../plantuml_data/boxes/renderer"
require_relative "../../plantuml_data/boxes/scene"
require_relative "../../plantuml_data/boxes/table_box"

module Sirena
  module Notation
    module PlantUML
      module NodeGraph
        # Draws a `json` element placed in a use case, component or
        # deployment diagram: the box a JSON diagram draws, with its corner
        # where the layout put the node.
        class DataShape
          Boxes = PlantUMLData::Boxes

          # @param placed [Placed]
          def initialize(placed)
            @placed = placed
          end

          # @return [Array<Svg::Element>]
          def elements
            Boxes::Renderer.new.render(scene).children
          end

          private

          def scene
            marks = Boxes::TableBox.draw(@placed.node.table, @placed.x,
                                         @placed.y)
            Boxes::Scene.new(width: @placed.x + @placed.width,
                             height: @placed.y + @placed.height, marks: marks)
          end
        end
      end
    end
  end
end
