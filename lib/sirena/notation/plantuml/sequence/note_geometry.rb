# frozen_string_literal: true

require_relative "../creole"
require_relative "../drawing"

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # Size and horizontal place of a note, shared by the layout (which
        # widens gaps for it) and the walker (which draws it).
        module NoteGeometry
          extend self

          PAD = 8.0
          SKIN_FONT_SIZE = 13.0
          OFFSET = 6.0
          OVER_MARGIN = 10.0
          BLOCK_GAP = 5.0
          PICTURE_CHROME = 15.0
          LINE_LEADING = 1.1776
          # PlantUML 1.2026.6 sizes a note box as 10 + 15 per line, though
          # the text inside steps by the font's own leading.
          LINE_PITCH = 15.0
          CHROME = 10.0
          FIRST_BASELINE = 17.568
          private_constant :LINE_PITCH, :CHROME

          # Width the text needs, without regard to the participants.
          def natural_width(note, font_size)
            return picture_width(note.picture) + (2 * PAD) if note.picture

            widest = note.lines.map { |line| line_width(line, font_size) }
            widest.max + (2 * PAD)
          end

          # A line is as wide as it is drawn, in the face the other sequence
          # text is measured in: creole markers and tags take no room, a bold
          # run is measured bold, a `<size:N>` run at its own size, and a
          # monospace run (`""..""`, an undecoded image) in the mono face.
          def line_width(line, font_size, bold: false)
            Creole.parse(line).sum { |run| run_width(run, font_size, bold) }
          end

          # The widest line of a multi-line label (a newline or a literal
          # backslash-n splits it), each line measured as drawn.
          def widest_line(text, font_size, bold: false)
            lines = text.to_s.split(/\\n|\n/, -1)
            lines.map { |l| line_width(l, font_size, bold: bold) }.max.to_f
          end

          def line_height(font_size)
            font_size * LINE_LEADING
          end

          def height(note)
            return picture_height(note.picture) + 14 if note.picture

            (note.lines.size * LINE_PITCH) + CHROME
          end

          def picture_inset(picture)
            nested = picture.scene.notes.any?(&:picture)
            nested ? PICTURE_CHROME * picture.scale : 0.0
          end

          def picture_width(picture)
            picture.width - (2 * picture_inset(picture))
          end

          def picture_height(picture)
            picture.height - (2 * picture_inset(picture))
          end

          # @return [Array<Integer>] first and last participant index the
          #   note refers to
          def span(note, previous, ids)
            return [0, ids.size - 1] if note.side == :across
            return message_span(previous, ids) if note.attached?

            note.targets.map { |id| ids.index(id) }.minmax
          end

          # Where a note on a closed block goes: right of the block, whichever
          # side the source names, level with its top. `block` is the
          # {FragmentShape}.
          #
          # @return [Array<Float>] left edge and width
          def beside(block, natural)
            [block.x + block.width + BLOCK_GAP, natural]
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

          def run_width(run, font_size, bold)
            size = run.style[:size].to_f
            size = font_size unless size.positive?
            if run.style[:mono]
              return TextMeasurement.measure_mono(run.text,
                                                  font_size: size)[:width]
            end

            Drawing::Face.width(run.text, size: size,
                                          bold: bold || run.style[:bold])
          end

          def message_span(message, ids)
            message.participants.map { |id| ids.index(id) }.minmax
          end
        end
      end
    end
  end
end
