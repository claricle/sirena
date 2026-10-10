# frozen_string_literal: true

require_relative "../../diagram/sequence_text"
require_relative "text_width"

module Sirena
  module Layout
    class Sequence < Base
      # Breaks sequence text into lines the way mermaid's wrapLabel does:
      # words are packed greedily, and a word wider than the limit is cut
      # into hyphenated pieces. Text that already holds a `<br>` is left
      # alone. Widths come from TextWidth.
      class TextWrap
        LINE_BREAK = Diagram::SequenceText::LINE_BREAK
        WRAP_ON = /\A\s*wrap:/i
        WRAP_OFF = /\A\s*nowrap:/i
        HYPHEN = "-"

        # @param source [String] text as written, `wrap:` prefix included
        # @param global [Boolean] the diagram's wrap setting
        # @return [Boolean] whether mermaid wraps this text
        def self.wrapped?(source, global)
          return true if source.match?(WRAP_ON)

          global && !source.match?(WRAP_OFF)
        end

        # @param source [String] text as written, `wrap:` prefix included
        # @return [String] the text without its `wrap:`/`nowrap:` prefix
        def self.body(source)
          source.sub(Diagram::SequenceText::WRAP_PREFIX, "")
        end

        # @param text [String] text without its prefix
        # @param limit [Numeric] widest a line may be before it breaks
        # @param size [Numeric] font size in pixels
        # @return [Array<String>] the lines, as the source writes them
        def self.lines(text, limit, size)
          return text.split(LINE_BREAK, -1) if text.match?(LINE_BREAK)

          new(limit, size).lines(text)
        end

        def initialize(limit, size)
          @limit = limit
          @size = size
        end

        def lines(text)
          done = []
          line = ""
          text.split(/ /).reject(&:empty?).each do |word|
            line = place(word, line, done)
          end
          done.push(line).reject(&:empty?)
        end

        private

        def place(word, line, done)
          if width("#{word} ") > @limit
            pieces, rest = break_word(word)
            done.push(line, *pieces)
            rest
          elsif width(line) + width("#{word} ") >= @limit
            done.push(line)
            word
          else
            [line, word].reject(&:empty?).join(" ")
          end
        end

        def break_word(word)
          pieces = []
          line = +""
          chars = word.chars
          chars.each_with_index do |char, index|
            line << char
            next if width(line) < @limit

            pieces << (index == chars.length - 1 ? line : line + HYPHEN)
            line = +""
          end
          [pieces, line]
        end

        def width(line)
          TextWidth.of(line, @size)
        end
      end
    end
  end
end
