# frozen_string_literal: true

require_relative "../markdown_text"
require_relative "../text_measurement"

module Sirena
  module Layout
    # Wraps a Kanban card's parsed label text to a pixel width, the way
    # mermaid-js does, instead of cutting it. Hard line breaks stay line
    # breaks; a word wider than the width is split by character.
    class KanbanCardText
      # @param text [String] raw card text, markdown markers allowed
      # @param width [Numeric] wrap width in pixels
      # @param font_size [Numeric] font size used to measure
      # @return [Array<Array<Sirena::MarkdownText::Run>>] one run array
      #   per rendered line
      def self.lines(text, width:, font_size:)
        wrapper = new(width, font_size)
        Sirena::MarkdownText.parse_lines(text).flat_map do |runs|
          wrapper.wrap(runs)
        end
      end

      def initialize(width, font_size)
        @width = width
        @font_size = font_size
      end

      # @param runs [Array<Sirena::MarkdownText::Run>] one hard line
      # @return [Array<Array<Sirena::MarkdownText::Run>>]
      def wrap(runs)
        lines = [[]]
        used = 0.0
        pieces(runs).each do |run, piece|
          size = measure(piece)
          if wraps?(lines.last, used, size)
            lines << []
            used = 0.0
          end
          next if skip_space?(piece, lines)

          lines.last << [run, piece]
          used += size
        end
        lines.map { |line| merge(line) }
      end

      private

      def wraps?(line, used, size)
        !line.empty? && used + size > @width
      end

      def skip_space?(piece, lines)
        piece.strip.empty? && lines.last.empty? && lines.length > 1
      end

      def pieces(runs)
        runs.flat_map do |run|
          run.text.scan(/\s+|\S+/).flat_map do |token|
            split_wide(token).map { |piece| [run, piece] }
          end
        end
      end

      def split_wide(token)
        return [token] if measure(token) <= @width

        token.chars.each_with_object([+""]) do |char, chunks|
          chunks << +"" if measure(chunks.last + char) > @width &&
                           !chunks.last.empty?
          chunks.last << char
        end
      end

      def measure(text)
        TextMeasurement.measure(text, font_size: @font_size)[:width]
      end

      def merge(line)
        merged = line.chunk_while { |a, b| a.first == b.first }.map do |group|
          group.first.first.with(text: group.map(&:last).join)
        end
        trim_end(merged)
      end

      def trim_end(runs)
        return runs if runs.empty?

        runs[0...-1] + [runs.last.with(text: runs.last.text.rstrip)]
      end
    end
  end
end
