# frozen_string_literal: true

require_relative "../../text_measurement"
require_relative "../../text_measurement/times_advances"

module Sirena
  module Layout
    class Sequence < Base
      # Width of one line of sequence text as mmdc measures it.
      #
      # mermaid measures with no font family set, so the browser falls back
      # to Times New Roman, whatever face the text is drawn in. A line is
      # rounded to whole pixels. A character reference such as `#9829;` is
      # measured in the placeholder form mermaid encodes it to, not as the
      # character it draws as. Pair adjustments use Times New Roman's
      # per-mille kerning units.
      class TextWidth
        TABLE = TextMeasurement::TimesAdvances::TABLE
        KERNING = {
          "Fi" => -20,
          "Wo" => -80,
        }.freeze
        REFERENCE = /#(\w+);/
        NUMERIC = /\A\+?\d+\z/
        MARK = "ﬂ°"
        END_MARK = "¶ß"

        # @param line [String] one line of text, as written in the source
        # @param font_size [Numeric] text size in pixels
        # @return [Integer] the line's width in whole pixels
        def self.of(line, font_size)
          characters = collapse(encode(line)).each_char.to_a
          advances = characters.sum { |char| advance(char) }
          advances += characters.each_cons(2).sum { |pair| kerning(pair) }
          ((advances * font_size / 1000.0) + 0.5).floor
        end

        # @param lines [Array<String>] lines of text
        # @return [Integer] the widest line, 0 when there are none
        def self.widest(lines, font_size)
          lines.map { |line| of(line, font_size) }.max || 0
        end

        def self.encode(line)
          line.gsub(REFERENCE) do
            name = Regexp.last_match(1)
            "#{MARK}#{'°' if name.match?(NUMERIC)}#{name}#{END_MARK}"
          end
        end

        # SVG text drops leading and trailing spaces and folds the rest.
        def self.collapse(line)
          line.gsub(/\s+/, " ").strip
        end

        def self.advance(char)
          TABLE.fetch(char.ord) do
            TextMeasurement.measure(char, font_size: 1000)[:width]
          end
        end

        def self.kerning(pair)
          KERNING.fetch(pair.join, 0)
        end
        private_class_method :encode, :collapse, :advance, :kerning
      end
    end
  end
end
