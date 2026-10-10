# frozen_string_literal: true

require_relative "../text_measurement"

module Sirena
  module Layout
    # The actor legend of a user journey, laid out the way mmdc does it.
    #
    # Actors are listed alphabetically, one row each, starting at y=60 and
    # 20px apart. A name wider than LABEL_WIDTH wraps on spaces (a single
    # word wider than that is cut with a hyphen) and the row grows by 20px
    # per extra line. The widest line pushes the diagram right, but only
    # once it is wider than half of BASE_MARGIN.
    class UserJourneyLegend
      FONT_SIZE = 16
      LABEL_WIDTH = 360
      BASE_MARGIN = 150
      FIRST_ROW_Y = 60
      ROW_STEP = 20

      # @param names [Array<String>] actor names in any order
      def initialize(names)
        @names = names.uniq.sort
      end

      # @return [Array<Array>] [name, index, y, lines] per actor
      def rows
        y_position = FIRST_ROW_Y
        @names.each_with_index.map do |name, index|
          lines = wrap(name)
          row = [name, index, y_position, lines]
          y_position += [ROW_STEP, lines.length * ROW_STEP].max
          row
        end
      end

      # @return [Numeric] x of the first task column
      def left_margin
        widest = rows.flat_map { |row| row[3] }.map { |line| width(line) }
          .select { |line_width| line_width > BASE_MARGIN - line_width }.max
        BASE_MARGIN + (widest || 0)
      end

      private

      def wrap(name)
        return [name] if width(name) <= LABEL_WIDTH

        lines = []
        current = +""
        name.split(" ", -1).each do |word|
          current = add_word(lines, current, word)
        end
        lines << current unless current.empty?
        lines
      end

      def add_word(lines, current, word)
        candidate = current.empty? ? word : "#{current} #{word}"
        return candidate if width(candidate) <= LABEL_WIDTH

        lines << current unless current.empty?
        width(word) > LABEL_WIDTH ? break_word(lines, word) : word
      end

      def break_word(lines, word)
        piece = +""
        word.each_char do |char|
          if width("#{piece}#{char}-") > LABEL_WIDTH
            lines << "#{piece}-"
            piece = +""
          end
          piece << char
        end
        piece
      end

      def width(text)
        TextMeasurement.measure(text, font_size: FONT_SIZE)[:width]
      end
    end
  end
end
