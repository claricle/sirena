# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Sequence
        module IRAdapter
          # Encodes the colour written after a participant or a note.
          module Fills
            module_function

            # @param fill [Fill, nil] nothing is written for nil
            def call(parent, fill, sink)
              return unless fill

              sink.detail(parent, "fill_colour", fill.colour)
              sink.detail(parent, "fill_opacity", fill.opacity)
            end
          end
        end
      end
    end
  end
end
