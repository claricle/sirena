# frozen_string_literal: true

require_relative "../svg/tspan"

module Sirena
  module Renderer
    # Parses mermaid's markdown subset used inside diagram label text: bold
    # (`**text**`), italic (`*text*`, nestable with bold), and a literal
    # newline as a hard line break. Nothing else — no code spans, links,
    # headers or lists. See docs/plans/kanban-markdown-labels.md for the
    # mmdc measurements this subset and its flanking rule are drawn from.
    #
    # Not a general markdown parser: mermaid's own rendering of these labels
    # doesn't support more than this, and matching a real markdown gem's
    # output would diverge from the mmdc oracle sirena is scored against.
    #
    # Also builds the `<tspan>` runs a parsed label turns into on an
    # `Svg::Text` element, and truncates parsed lines to a visible-character
    # budget on run boundaries. Callers only ever need `parse_lines` plus
    # `assign_markdown_text` (optionally through `truncate_runs` first) — the
    # remaining methods are the private steps between them, `module_function`
    # like the rest of this module.
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

      # Assigns a markdown-parsed label onto a `Svg::Text` element.
      #
      # A label with no markup and no hard line break — the overwhelming
      # majority of label text — parses down to exactly the original
      # string in one unstyled run. That case keeps setting plain
      # `content`, unchanged from before this feature existed: no `<tspan>`
      # wrapper, same XML shape every existing corpus fixture and REXML
      # `.text` checks already expect. Only a label that actually needs
      # per-run styling or a line break pays for `<tspan>` children.
      #
      # @param text_element [Svg::Text] element to assign onto
      # @param lines [Array<Array<Run>>] from `parse_lines`, already
      #   truncated if truncation applies at this call site
      # @param x [Numeric] the label's horizontal anchor, passed through to
      #   `build_markdown_tspans`
      # @param base_font_weight [String, nil] passed through to
      #   `build_markdown_tspans`
      # @return [void]
      def assign_markdown_text(text_element, lines, x:, base_font_weight: nil)
        if plain_line?(lines)
          text_element.content = lines.first.first&.text.to_s
        else
          text_element.tspans = build_markdown_tspans(lines, x: x, base_font_weight: base_font_weight)
        end
      end

      # True when parsing found no markup and no hard line break: a single
      # line holding at most one run, styled neither bold nor italic.
      #
      # @param lines [Array<Array<Run>>]
      # @return [Boolean]
      # @api private
      def plain_line?(lines)
        return false unless lines.length == 1

        runs = lines.first
        runs.length <= 1 && runs.none? { |run| run.bold || run.italic }
      end

      # Builds the <tspan> runs for a markdown-parsed label.
      #
      # Every run in a line after the first line continues immediately
      # after the previous run — no `x`/`dy` needed, SVG just keeps
      # advancing horizontally. Only the FIRST run of a line that followed
      # a hard line break needs both: `x` to reset back to the label's left
      # edge (or center, for a middle-anchored header), and `dy` to move
      # down one line height. The very first line needs neither — it
      # starts at the parent <text> element's own x/y.
      #
      # @param lines [Array<Array<Run>>] from `parse_lines`, already
      #   truncated if truncation applies at this call site
      # @param x [Numeric] the label's horizontal anchor, repeated on every
      #   line-starting run after the first
      # @param base_font_weight [String, nil] "bold" when the surrounding
      #   `Svg::Text` is bold by default (e.g. a kanban column header), so a
      #   plain run still renders bold instead of losing the baseline weight
      # @return [Array<Svg::Tspan>]
      # @api private
      def build_markdown_tspans(lines, x:, base_font_weight: nil)
        lines.each_with_index.flat_map do |runs, line_index|
          runs.each_with_index.map do |run, run_index|
            new_line = line_index.positive? && run_index.zero?

            Svg::Tspan.new.tap do |t|
              t.x = x if new_line
              t.dy = "1.2em" if new_line
              t.font_weight = "bold" if run.bold || base_font_weight == "bold"
              t.font_style = "italic" if run.italic
              t.content = run.text
            end
          end
        end
      end

      # Truncates markdown-parsed lines to at most `max_length` visible
      # (post-markup) characters, cutting on run boundaries rather than
      # mid-marker.
      #
      # A run within the FIRST line may be cut partway through, with
      # "..." appended — this is the common case truncation exists for.
      # A later line (one that only exists because of a hard line break)
      # is kept whole or dropped whole, never cut partway through: mirrors
      # how the raw-string truncation this replaces already treated its
      # input as one unit, just applied after parsing instead of before.
      #
      # @param lines [Array<Array<Run>>]
      # @param max_length [Integer] maximum visible characters to keep
      # @return [Array<Array<Run>>]
      def truncate_runs(lines, max_length)
        budget = max_length
        result = []

        lines.each_with_index do |runs, line_index|
          line_length = runs.sum { |run| run.text.length }

          if line_length <= budget
            result << runs
            budget -= line_length
            next
          end

          result << truncate_line(runs, budget) if line_index.zero?
          break
        end

        result
      end

      # Cuts a single line's runs to `budget` visible characters, trimming
      # whole runs from the end and appending "..." to the run that
      # crosses the boundary.
      #
      # @param runs [Array<Run>]
      # @param budget [Integer] visible characters available
      # @return [Array<Run>]
      # @api private
      def truncate_line(runs, budget)
        remaining = budget
        kept = []

        runs.each do |run|
          if run.text.length <= remaining
            kept << run
            remaining -= run.text.length
          else
            visible = [remaining - 3, 0].max
            kept << run.with(text: "#{run.text[0, visible]}...")
            break
          end
        end

        kept
      end
    end
  end
end
