# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # SVG path data for the three note shapes: a folded corner for
        # `note`, a hexagon for `hnote` and a plain rectangle for `rnote`.
        module NoteShape
          extend self

          FOLD = 10.0

          def outline(shape, left, top, width, height)
            right = left + width
            bottom = top + height
            points = case shape
                     when :hnote then hexagon(left, top, right, bottom)
                     when :rnote then [[left, top], [right, top],
                                       [right, bottom], [left, bottom]]
                     else folded(left, top, right, bottom)
                     end
            "M #{points.map { |x, y| "#{x} #{y}" }.join(' L ')} Z"
          end

          # @return [String, nil] the crease of a folded corner
          def fold(shape, left, top, width)
            return unless shape == :note

            right = left + width
            "M #{right - FOLD} #{top} L #{right - FOLD} #{top + FOLD} " \
              "L #{right} #{top + FOLD}"
          end

          private

          def folded(left, top, right, bottom)
            [[left, top], [right - FOLD, top], [right, top + FOLD],
             [right, bottom], [left, bottom]]
          end

          def hexagon(left, top, right, bottom)
            middle = (top + bottom) / 2
            [[left + FOLD, top], [right - FOLD, top], [right, middle],
             [right - FOLD, bottom], [left + FOLD, bottom], [left, middle]]
          end
        end
      end
    end
  end
end
