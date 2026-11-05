# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module NodeGraph
        # The tab over the top left of a package, folder or frame, which
        # holds the first line of its name.
        module Tab
          HEIGHT = 20.0
          SLANT = 8.0
          PAD = 8.0

          module_function

          # @param left [Float] the container's left edge
          # @param top [Float] the container's top edge
          # @param width [Float] the width of the name
          # @return [String] the points of the tab's outline
          def points(left, top, width)
            right = left + width + (2 * PAD)
            [[left, top], [right, top], [right + SLANT, top + SLANT],
             [right + SLANT, top + HEIGHT], [left, top + HEIGHT]]
              .map { |point| point.join(",") }.join(" ")
          end
        end
      end
    end
  end
end
