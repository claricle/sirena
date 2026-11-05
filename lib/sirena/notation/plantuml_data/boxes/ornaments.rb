# frozen_string_literal: true

require_relative "marks"
require_relative "text"

module Sirena
  module Notation
    module PlantUMLData
      module Boxes
        # What a cell's markup draws that a text element cannot: the
        # background of `<back:..>`, the coloured line of `<s:..>` and
        # `<u:..>`, an Open Iconic glyph, and a placeholder where an emoji
        # goes (Twemoji is CC-BY 4.0 and its set is too large to bundle).
        module Ornaments
          extend self

          # Open Iconic outlines sit on an 8 grid; PlantUML scales them by
          # the font size over this.
          ICON_SCALE = 12.0
          ICON_LIFT = 9.88
          ICON_NUDGE = 0.75
          BACK_LIFT = 13.0
          BACK_HEIGHT = 16.5
          STRIKE_LIFT = 3.5
          UNDER_DROP = 1.0
          EMOJI_BOX = 14.0
          DRAWN = %i[back strike_colour underline_colour icon emoji].freeze
          private_constant :DRAWN
          # @return [Array<Hash>] the marks to draw under a text mark
          def behind(mark)
            each_piece(mark).filter_map do |piece, left, right|
              colour = piece.style[:back]
              next unless colour

              Marks.rect(left, mark[:y] - BACK_LIFT, right - left, BACK_HEIGHT,
                         rx: 0, fill: css(colour), stroke: "none",
                         stroke_width: 0)
            end
          end

          # @return [Array<Hash>] the marks to draw over a text mark
          def over(mark)
            each_piece(mark).flat_map do |piece, left, right|
              [*picture(piece, mark, left, right),
               *rule(piece, :strike_colour, mark[:y] - STRIKE_LIFT,
                     [left, right]),
               *rule(piece, :underline_colour, mark[:y] + UNDER_DROP,
                     [left, right])]
            end
          end

          private

          def each_piece(mark)
            return [] unless mark[:kind] == :text && mark[:content]

            runs = Text.runs(mark[:content])
            return [] if runs.all? { |piece| plain?(piece) }

            spans(runs, mark)
          end

          def plain?(piece)
            !piece.style.keys.intersect?(DRAWN)
          end

          def spans(runs, mark)
            widths = runs.map { |piece| Text.width(piece.text) }
            left = mark[:x] - anchor_shift(mark[:anchor], widths.sum)
            runs.zip(widths).map do |piece, width|
              span = [piece, left, left + width]
              left += width
              span
            end
          end

          def anchor_shift(anchor, total)
            anchor == "middle" ? total / 2 : 0.0
          end

          def rule(piece, key, height, span)
            return [] unless piece.style[key]

            [Marks.line([span[0], height], [span[1], height],
                        stroke: css(piece.style[key]), width: 0.5)]
          end

          def picture(piece, mark, left, right)
            if piece.style[:icon]
              [icon(piece.style[:icon], left, mark[:y], mark[:fill])]
            elsif piece.style[:emoji]
              [placeholder(left, right, mark[:y])]
            else
              []
            end
          end

          def icon(name, left, baseline, fill)
            { kind: :glyph, d: outline(name),
              fill: fill,
              transform: place(left + ICON_NUDGE, baseline - ICON_LIFT) }
          end

          # Loaded on first use, like {Text}: `require "sirena"` must not
          # define the PlantUML namespace.
          def outline(name)
            require_relative "../../plantuml/creole_icons"
            Sirena::Notation::PlantUML::Creole::Icons.outline(name)
          end

          def place(left, top)
            format("translate(%<x>.4f %<y>.4f) scale(%<k>.4f)",
                   x: left, y: top, k: Text::FONT_SIZE / ICON_SCALE)
          end

          def placeholder(left, right, baseline)
            side = EMOJI_BOX
            Marks.rect(left + ((right - left - side) / 2), baseline - side,
                       side, side, rx: 3, fill: "none", stroke: Marks::INK,
                                   stroke_width: 0.5)
          end

          def css(colour)
            colour.match?(/\A\h{3}(?:\h{3})?\z/) ? "##{colour}" : colour
          end
        end
      end
    end
  end
end
