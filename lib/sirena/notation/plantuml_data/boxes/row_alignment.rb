# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUMLData
      module Boxes
        # Where the JAR stands a box that is alone in its rank and linked
        # with a row of a map: beside the side its line leaves by, or, when
        # it is the one linking to the row, over the middle of the map.
        class RowAlignment
          # How far from the side of a map the middle of such a box lies.
          DRIFT = 5.5

          # @param links [Array<Link>]
          def initialize(links)
            @links = links
          end

          # @param rects [Hash{String => Rect}] each box where it stands
          # @param alone [Array<String>] the boxes alone in their rank
          # @return [Hash{String => Rect}] `rects`, the alone boxes moved
          #   across
          def call(rects, alone)
            rects.to_h do |id, rect|
              middle = alone.include?(id) && middle_of(id, rects)
              [id, middle ? rect.with(x: middle - (rect.width / 2)) : rect]
            end
          end

          private

          def middle_of(id, rects)
            from_row(id, rects) || over_map(id, rects)
          end

          def from_row(id, rects)
            link = @links.find { |l| l.to == id && l.from_row.is_a?(String) }
            link && side(link, rects.fetch(link.from))
          end

          def over_map(id, rects)
            link = @links.find { |l| l.from == id && l.to_row }
            link && rects.fetch(link.to).centre[0]
          end

          # Just past the side a map's row leaves by: the left one when
          # another line already ends at the row, otherwise the right.
          def side(link, rect)
            taken = @links.any? do |other|
              other.to == link.from && other.to_row == link.from_row
            end
            taken ? rect.x - DRIFT : rect.right + DRIFT
          end
        end
      end
    end
  end
end
