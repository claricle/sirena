# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # An embedded diagram after layout: its scene and the size it takes
        # in the note once scaled.
        class Picture
          attr_reader :scene, :scale

          def initialize(scene, scale)
            @scene = scene
            @scale = scale
            freeze
          end

          def width
            scene.width * scale
          end

          def height
            scene.height * scale
          end
        end
      end
    end
  end
end
