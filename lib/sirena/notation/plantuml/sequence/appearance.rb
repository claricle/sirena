# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # What skinparam and `<style>` set for a sequence diagram: the
        # narrowest participant head, how a head's lines sit against each
        # other, and the fill and text colour of a fragment's keyword tab.
        # A setting the source never made is nil, except `alignment`.
        class Appearance
          attr_reader :min_width, :tab_fill, :tab_colour

          def initialize(min_width: nil, alignment: nil, tab_fill: nil,
                         tab_colour: nil)
            @min_width = min_width
            @alignment = alignment
            @tab_fill = tab_fill
            @tab_colour = tab_colour
            freeze
          end

          # @return [Symbol] :left, :center or :right
          def alignment
            @alignment || :center
          end

          # @return [Appearance] this one with each setting `other` made
          def merge(other)
            Appearance.new(
              min_width: other.min_width || min_width,
              alignment: other.explicit_alignment || @alignment,
              tab_fill: other.tab_fill || tab_fill,
              tab_colour: other.tab_colour || tab_colour,
            )
          end

          protected

          def explicit_alignment
            @alignment
          end
        end
      end
    end
  end
end
