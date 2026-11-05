# frozen_string_literal: true

require_relative "marks"

module Sirena
  module Notation
    module PlantUMLData
      module Boxes
        # The texts of a relation, placed as the JAR does: the label starts
        # just right of the middle of the line, the text of an end finishes
        # just left of it, a line's height from that end.
        module LinkText
          extend self

          LABEL_GAP = 1.0
          LABEL_DROP = 5.2
          END_GAP = 1.4
          TAIL_DROP = 20.2
          HEAD_RISE = 10.4

          # @return [Array<Hash>] text marks for `link`, drawn from `start`
          #   to `stop`
          def call(link, start, stop)
            [label(link, start, stop), tail(link, start),
             head(link, stop)].compact
          end

          private

          def label(link, start, stop)
            middle = start.zip(stop).map { |a, b| (a + b) / 2 }
            text(link.label, middle[0] + LABEL_GAP, middle[1] + LABEL_DROP)
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
