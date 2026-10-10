# frozen_string_literal: true

require_relative "../fill"

module Sirena
  module Notation
    module PlantUML
      module Sequence
        module IRReader
          # Rebuilds the colour written after a participant or a note.
          module Fills
            module_function

            # @return [Fill, nil]
            def call(node, index)
              colour = index.detail(node, "fill_colour")
              return unless colour

              opacity = index.detail(node, "fill_opacity")
              Fill.new(colour, opacity && (opacity.to_f * 255).round)
            end
          end
        end
      end
    end
  end
end
