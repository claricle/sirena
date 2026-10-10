# frozen_string_literal: true

require_relative "scene"

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # The title line above a sequence diagram: how much room it takes
        # and where its text sits.
        module TitleRow
          extend self

          ROOM = 37.49
          BASELINE = 23.54
          SIDE = 5.0

          # @return [Float] the height the title pushes the diagram down by
          def room(title)
            title ? ROOM : 0.0
          end

          # @return [Float] the width the title needs on its own
          def width(title, measure)
            title ? measure.call(title) + (2 * SIDE) : 0.0
          end

          # @param top [Float] the y the title row starts at
          # @param canvas [Float] the full width the title is centred in
          # @return [Scene::Title, nil]
          def scene(title, top, canvas)
            return unless title

            Scene::Title.new(
              texts: [PlantUML::Scene::Text.new(
                content: title, x: canvas / 2, y: top + BASELINE,
                role: "title", anchor: "middle"
              )],
            )
          end
        end
      end
    end
  end
end
