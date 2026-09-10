# frozen_string_literal: true

module Sirena
  module Renderer
    # Parses mermaid's markdown subset used inside kanban card and column
    # labels: bold (`**text**`), italic (`*text*`, nestable with bold), and
    # a literal newline as a hard line break. Nothing else — no code spans,
    # links, headers or lists. See docs/plans/kanban-markdown-labels.md for
    # the mmdc measurements this subset and its flanking rule are drawn from.
    #
    # Not a general markdown parser: mermaid's own rendering of these labels
    # doesn't support more than this, and matching a real markdown gem's
    # output would diverge from the mmdc oracle sirena is scored against.
    module MarkdownText
      # One styled run of text. `bold` and `italic` are independent booleans
      # rather than a single "style" enum because nesting (`**bold *and
      # italic* end**`) produces a run that is both at once.
      Run = Data.define(:text, :bold, :italic)

      BOLD = '**'
      ITALIC = '*'

      module_function

      # Splits text on hard line breaks and parses each line's markup.
      #
      # @param text [String] raw label text, possibly containing `**`/`*`
      #   markers and literal newlines
      # @return [Array<Array<Run>>] one run array per line
      def parse_lines(text)
        text.to_s.split("\n", -1).map { |line| parse_line(line) }
      end

      # @api private
      def parse_line(line)
        scan(line, bold: false, italic: false)
      end

      # Recursive-descent scan of one line (or the inner content of an
      # already-opened marker). Returns a flat run list: nesting is
      # represented by the returned runs' bold/italic flags, not by any
      # tree structure the caller has to walk.
      #
      # @api private
      def scan(text, bold:, italic:)
        runs = []
        buffer = +''
        i = 0

        while i < text.length
          marker = marker_at(text, i)

          if marker && (close_at = closer_for(text, i, marker))
            runs << Run.new(text: buffer, bold: bold, italic: italic) unless buffer.empty?
            buffer = +''
            inner_start = i + marker.length
            runs.concat(scan(text[inner_start...close_at],
                             bold: bold || marker == BOLD,
                             italic: italic || marker == ITALIC))
            i = close_at + marker.length
          elsif marker
            buffer << marker
            i += marker.length
          else
            buffer << text[i]
            i += 1
          end
        end

        runs << Run.new(text: buffer, bold: bold, italic: italic) unless buffer.empty?
        runs
      end

      # The longer marker always wins: `**` is checked before `*`, so a
      # bold delimiter is never seen as two independent italic ones.
      #
      # @api private
      def marker_at(text, i)
        return BOLD if text[i, 2] == BOLD
        return ITALIC if text[i] == ITALIC

        nil
      end

      # A marker only opens when the character right after it is not
      # whitespace, and only closes when the character right before it is
      # not whitespace. `closer_for` returns nil (never opens) when the
      # candidate itself fails the opening half of that rule, so a caller
      # never has to check both halves separately.
      #
      # @api private
      def closer_for(text, open_at, marker)
        return nil unless flanked_open?(text, open_at, marker)

        pos = open_at + marker.length

        while (idx = text.index(marker, pos))
          return idx if flanked_close?(text, idx)

          pos = idx + marker.length
        end

        nil
      end

      # @api private
      def flanked_open?(text, open_at, marker)
        next_char = text[open_at + marker.length]
        !next_char.nil? && !next_char.match?(/\s/)
      end

      # @api private
      def flanked_close?(text, close_at)
        !text[close_at - 1].match?(/\s/)
      end
    end
  end
end
