# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # A `|||` or `||N||` line: blank room between two rows. `height` is
        # the N pixels written, or nil for the bare form, which PlantUML
        # draws as {DEFAULT} pixels.
        class Spacing
          DEFAULT = 25.0

          attr_reader :height

          def initialize(height: nil)
            @height = height
            freeze
          end

          # @return [Float] the room the line adds, in pixels
          def room
            height || DEFAULT
          end
        end
      end
    end
  end
end
