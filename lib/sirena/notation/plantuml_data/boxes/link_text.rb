# frozen_string_literal: true

require_relative "marks"
require_relative "text"
require_relative "../../../text_measurement"
require_relative "../../plantuml/label_clearance"

module Sirena
  module Notation
    module PlantUMLData
      module Boxes
        # The texts of a relation, placed as the JAR does: the label of a
        # steep line starts just right of its middle, the label of a flat one
        # is centred on its middle with its foot on the line's highest point
        # under it, the text of an end finishes just left of it, a line's
        # height from that end.
        module LinkText
          extend self

          LABEL_GAP = 1.0
          LABEL_DROP = 5.2
          END_GAP = 1.4
          TAIL_DROP = 20.2
          HEAD_RISE = 10.4
          # How far right of the middle a flat line's label is centred, and
          # how far its baseline rises over the line (0.264 of the font).
          FLAT_SHIFT = 2.8
          FLAT_RISE = 3.7

          # @return [Array<Hash>] text marks for `link`, drawn from `start`
          #   to `stop`
          def call(link, start, stop)
            [label(link, start, stop), tail(link, start),
             head(link, stop)].compact
          end

          private

          def label(link, start, stop)
            return if link.label.to_s.empty?
            return flat_label(link.label, start, stop) if flat?(start, stop)

            steep_label(link.label, start, stop)
          end

          def flat?(start, stop)
            (stop[0] - start[0]).abs > (stop[1] - start[1]).abs
          end

          def flat_label(content, start, stop)
            centre = ((start[0] + stop[0]) / 2) + FLAT_SHIFT
            half = width_of(content) / 2
            top = PlantUML::LabelClearance.top_between(
              start, stop, centre - half, centre + half
            )
            text(content, centre, top - FLAT_RISE, "middle")
          end

          # Right of the line, past its furthest point under the text.
          def steep_label(content, start, stop)
            middle = ((start[1] + stop[1]) / 2) + LABEL_DROP
            reach = PlantUML::LabelClearance.right_between(
              start, stop, middle - Text::FONT_SIZE, middle
            )
            text(content, [reach, (start[0] + stop[0]) / 2].max + LABEL_GAP,
                 middle)
          end

          # Measured in DejaVu Sans, the face the picture is drawn in.
          def width_of(content)
            TextMeasurement.measure_in(:dejavu, Text.plain(content),
                                       font_size: Text::FONT_SIZE)[:width]
          end

          def tail(link, start)
            text(link.tail_text, start[0] - END_GAP, start[1] + TAIL_DROP,
                 "end")
          end

          def head(link, stop)
            text(link.head_text, stop[0] - END_GAP, stop[1] - HEAD_RISE, "end")
          end

          def text(content, left, baseline, anchor = nil)
            return if content.to_s.empty?

            Marks.text(content, left, baseline - Marks::BASELINE,
                       anchor: anchor)
          end
        end
      end
    end
  end
end
