# frozen_string_literal: true

require_relative "timing/reader"
require_relative "timing/layout"
require_relative "drawing"

module Sirena
  module Notation
    module PlantUML
      # The PlantUML timing diagram: one track per participant (robust,
      # concise, clock, binary or analog) over a shared time axis, with
      # messages between tracks and highlighted bands.
      module Timing
        extend self

        # Only a timing diagram declares one of these; the lines are a
        # declaration of a participant, so no other family reads them.
        DECLARATION = /^[ \t]*(?:robust|concise|clock|binary|analog)[ \t]+
                       (?:"[^"\n]+"[ \t]+as[ \t]+)?[A-Za-z_]\w*/xi
        private_constant :DECLARATION

        # @return [Boolean] whether the source declares a timing participant
        def timing?(source)
          source.dup.force_encoding(Encoding::UTF_8).scrub
            .match?(DECLARATION)
        end

        # @return [Notation::Parsed]
        def parse(source)
          Notation::Parsed.new(
            type: :timing_diagram, diagram: Reader.new.parse(source),
            transform: Layout, renderer: Drawing::Renderer
          )
        end
      end
    end
  end
end
