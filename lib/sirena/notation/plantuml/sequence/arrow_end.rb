# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # What is drawn at one end of an arrow. `glyph` is nil, :filled,
        # :open, :upper, :lower, :upper_open, :lower_open or :cross; the
        # half and cross glyphs are the ones written `\`, `/` and `x`.
        # `circle` adds the ring written `o`.
        class ArrowEnd
          attr_reader :glyph, :circle

          def initialize(glyph: nil, circle: false)
            @glyph = glyph
            @circle = circle
            freeze
          end
        end
      end
    end
  end
end
