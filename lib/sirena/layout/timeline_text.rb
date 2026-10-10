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
        def wrap(text, width)
          lines = []
          line = []
          text.to_s.split(TOKENS).each do |word|
            line << word
            next unless word == BREAK || width_of(join(line)) > width

            line.pop
            lines << join(line)
            line = word == BREAK ? [""] : [word]
          end
          lines << join(line)
        end

        # @return [Float] width of one line in user units
        def width_of(line)
          advances = join([line]).each_char.sum { |char| advance(char) }
          advances * FONT_SIZE / 1000.0
        end

        # @return [Float] height of the drawn text, blank lines not counted
        def text_height(lines)
          drawn = lines.count { |line| !line.empty? }
          return 0.0 if drawn.zero?

          FIRST_LINE_HEIGHT + ((drawn - 1) * NEXT_LINE_HEIGHT)
        end

        # @return [Float] card height the text needs before any minimum
        def card_height(lines)
          text_height(lines) + TEXT_MARGIN + PADDING
        end

        private

        def join(words)
          words.join(" ").gsub(/\s+/, " ").strip
        end

        def advance(char)
          TABLE.fetch(char.ord) do
            TextMeasurement.measure(char, font_size: 1000)[:width]
          end
        end
      end
    end
  end
end
