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
      DESIGN_UNITS_PER_EM = 2048.0
      BASIC_LATIN_START = 0x20
      # Exact hmtx units for U+0020..U+007E in Trebuchet MS Regular. The
      # shared per-mille table intentionally rounds each glyph; long labels
      # accumulate those sub-unit losses before the browser measures them.
      BASIC_LATIN_UNITS = %w[
        617 752 665 1074 1074 1229 1446 327 752 752 752 1074 752 752 752 1074
        1074 1074 1074 1074 1074 1074 1074 1074 1074 1074 752 752 1074 1074
        1074 752 1578 1208 1159 1225 1256 1097 1075 1385 1340 570 976 1179
        1037 1453 1307 1380 1142 1384 1192 985 1189 1328 1203 1745 1140 1168
        1127 752 728 752 1074 1074 1074 1076 1141 1014 1141 1117 757 1028
        1119 584 751 1033 604 1700 1119 1099 1141 1141 796 829 812 1119 1003
        1524 1026 1010 972 752 1074 752 1074
      ].map!(&:to_i).freeze

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
          units = join([line]).each_char.sum { |char| design_units(char) }
          units * font_size / DESIGN_UNITS_PER_EM
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

        def design_units(char)
          index = char.ord - BASIC_LATIN_START
          return BASIC_LATIN_UNITS.fetch(index) if
            index.between?(0, BASIC_LATIN_UNITS.length - 1)

          (advance(char) * DESIGN_UNITS_PER_EM / 1000).round
        end

        def scaled(value, font_size)
          value * font_size / FONT_SIZE.to_f
        end
      end
    end
  end
end
