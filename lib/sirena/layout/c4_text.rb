# frozen_string_literal: true

require_relative "../text_measurement"

module Sirena
  module Layout
    # Text sizes as mermaid's C4 renderer takes them from the browser: the
    # widest line's width rounded to a whole pixel, and a fixed height per
    # non-empty line. An empty line has no height, so an empty label adds
    # nothing to a C4 element.
    module C4Text
      LINE_BREAK = %r{<br\s*/?>}i
      LINE_HEIGHTS = { 12 => 14, 14 => 16, 16 => 17 }.freeze
      LINE_HEIGHT_RATIO = 1.15

      module_function

      # @param text [String, nil] text that may hold <br/> breaks
      # @return [Array<String>] the lines, never empty
      def lines(text)
        parts = text.to_s.split(LINE_BREAK, -1).map(&:strip)
        parts.empty? ? [""] : parts
      end

      def width(text, font_size)
        lines(text).map { |line| line_width(line, font_size) }.max
      end

      def height(text, font_size)
        lines(text).sum { |line| line_height(line, font_size) }
      end

      def line_width(line, font_size)
        TextMeasurement.measure(line, font_size: font_size)[:width].round
      end

      def line_height(line, font_size)
        return 0 if line.empty?

        LINE_HEIGHTS.fetch(font_size) { (font_size * LINE_HEIGHT_RATIO).round }
      end
    end
  end
end
