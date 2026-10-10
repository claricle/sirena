# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # Size and horizontal place of a note, shared by the layout (which
        # widens gaps for it) and the walker (which draws it).
        module NoteGeometry
          extend self

          PAD = 8.0
          OFFSET = 6.0
          OVER_MARGIN = 10.0

          # Width the text needs, without regard to the participants.
          def natural_width(note, measure)
            note.lines.map { |line| measure.call(line) }.max + (2 * PAD)
          end

          def line_height(font_size)
            font_size * 1.3
          end

          def height(note, font_size)
            (note.lines.size * line_height(font_size)) + 14
          end

          # @return [Array<Integer>] first and last participant index the
          #   note refers to
          def span(note, previous, ids)
            return [0, ids.size - 1] if note.side == :across
            return message_span(previous, ids) if note.attached?

            note.targets.map { |id| ids.index(id) }.minmax
          end

          # @return [Array<Float>] left edge and width
          def box(note, centers, natural)
            low, high = centers
            case note.side
            when :left then [low - OFFSET - natural, natural]
            when :right then [high + OFFSET, natural]
            else
              width = [natural, high - low + (2 * OVER_MARGIN)].max
              [((low + high) / 2) - (width / 2), width]
            end
          end

          private

          def message_span(message, ids)
            message.participants.map { |id| ids.index(id) }.minmax
          end
        end
      end
    end
  end
end
