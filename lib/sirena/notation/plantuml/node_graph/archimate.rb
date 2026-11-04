# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module NodeGraph
        # `archimate #Layer "Name" as id <<archimate-type>>`. The layer name
        # is a colour in PlantUML; the type's icon is not drawn, so the
        # element is a plain box carrying its label.
        module Archimate
          LAYERS = {
            "business" => "#FFFFB5", "application" => "#B5FFFF",
            "technology" => "#C9E7B7", "physical" => "#C9E7B7",
            "motivation" => "#EFBDEB", "strategy" => "#F5DEAA",
            "implementation" => "#FFE0E0", "migration" => "#FFE0E0",
            "other" => "#FFFFFF"
          }.freeze

          module_function

          # @param color [String, nil] a layer name or an ordinary colour
          # @return [String, nil] the colour the layer stands for, else
          #   `color` itself
          def color(color)
            LAYERS.fetch(color.to_s.downcase, color)&.delete_prefix("#")
          end
        end
      end
    end
  end
end
