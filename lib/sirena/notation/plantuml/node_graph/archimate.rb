# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module NodeGraph
        # `archimate #Layer "Name" as id <<archimate-type>>`. The layer name
        # is a colour in PlantUML, filled as the JAR 1.2026.6 fills it. Only
        # the technology device's icon is drawn; any other element is a
        # plain box carrying its label.
        module Archimate
          LAYERS = {
            "business" => "#FFFFCC", "application" => "#C2F0FF",
            "technology" => "#C9FFC9", "physical" => "#97FF97",
            "motivation" => "#CCCCFF", "strategy" => "#F8E7C0",
            "implementation" => "#FFE0E0", "migration" => "#FFE0E0",
            "other" => "#FFFFFF"
          }.freeze

          # The device icon in its own coordinates, 17 wide and 14 tall,
          # as PlantUML draws it for `<<technology-device>>`.
          DEVICE = "M0.59,0 A0.5,0.5 0 0 0 0.09,0.5 L0,10.42 A0.5,0.5 0 0 0 " \
                   "0.5,10.92 L3.54,10.92 L1.28,13.05 A0.5,0.5 0 0 0 1.62," \
                   "13.91 L15.56,13.96 A0.5,0.5 0 0 0 15.94,13.13 L14,10.92 " \
                   "L16.68,10.92 A0.5,0.5 0 0 0 17.18,10.42 L17.14,0.5 A0.5," \
                   "0.5 0 0 0 16.64,0 M1.09,1 L16.14,1 L16.18,9.92 L1,9.92 " \
                   "M4.47,11.42 L13.11,11.42 L14.46,12.95 L2.88,12.91"
          SPRITES = { "technology-device" => DEVICE }.freeze
          SPRITE_ROOM = 20.0

          module_function

          # @param stereotype [String, nil] the `<<archimate-type>>` text
          # @return [String, nil] the path of the type's icon, when drawn
          def sprite(stereotype)
            SPRITES[stereotype.to_s.strip.downcase]
          end

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
