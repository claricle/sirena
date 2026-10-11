# frozen_string_literal: true

require_relative "../text_measurement"
require_relative "../text_measurement/trebuchet_advances"

module Sirena
  module Layout
    # Wraps and sizes timeline card text the way mmdc does: words are added
    # to a line until it passes the card text width, then the line breaks.
    # Widths are Trebuchet MS advances, the face mmdc measured with.
    class TimelineText
      FONT_SIZE = 16
      FIRST_LINE_HEIGHT = 19.0
      NEXT_LINE_HEIGHT = 17.6
      # Space under the text that every card keeps, besides its padding.
      TEXT_MARGIN = FONT_SIZE * 1.1 * 0.5
      PADDING = 20
      TOKENS = /(\s+|<br>)/
      BREAK = "<br>"
      TABLE = TextMeasurement::TrebuchetAdvances::TABLE

      class << self
        # @param text [String] label text, possibly holding <br>
        # @param width [Numeric] text width at which a line breaks
        # @return [Array<String>] the lines, whitespace collapsed
        def wrap(text, width, font_size: FONT_SIZE)
          lines = []
          line = []
          text.to_s.split(TOKENS).each do |word|
            line << word
            next unless line_break?(word, line, width, font_size)

            line.pop
            lines << join(line)
            line = word == BREAK ? [""] : [word]
          end
          lines << join(line)
        end

        # @return [Float] width of one line in user units
        def width_of(line, font_size: FONT_SIZE)
          advances = join([line]).each_char.sum { |char| advance(char) }
          advances * font_size / 1000.0
        end

        # @return [Float] height of the drawn text, blank lines not counted
        def text_height(lines, font_size: FONT_SIZE)
          drawn = lines.count { |line| !line.empty? }
          return 0.0 if drawn.zero?

          scaled(FIRST_LINE_HEIGHT, font_size) +
            ((drawn - 1) * scaled(NEXT_LINE_HEIGHT, font_size))
        end

        # @return [Float] card height the text needs before any minimum
        def card_height(lines, font_size: FONT_SIZE)
          margin = scaled(TEXT_MARGIN, font_size)
          text_height(lines, font_size: font_size) + margin + PADDING
        end

        private

        def line_break?(word, line, width, font_size)
          word == BREAK || width_of(join(line), font_size: font_size) > width
        end

        def join(words)
          words.join(" ").gsub(/\s+/, " ").strip
        end

        def advance(char)
          TABLE.fetch(char.ord) do
            TextMeasurement.measure(char, font_size: 1000)[:width]
          end
        end

        def scaled(value, font_size)
          value * font_size / FONT_SIZE.to_f
        end
      end
    end
  end
end
