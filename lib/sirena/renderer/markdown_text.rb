# frozen_string_literal: true

require "kramdown"
require_relative "../svg/tspan"

module Sirena
  module Renderer
    # Parses mermaid's markdown subset used inside diagram label text: bold
    # (`**text**`), italic (`*text*`, nestable with bold, in either order,
    # including `***both***`), and a literal newline as a hard line break —
    # including one embedded inside a bold/italic run, which keeps that
    # run's styling on both sides of the break. Nothing else — no code
    # spans, links, headers or lists; mermaid's own rendering of these
    # labels doesn't support more than this. See
    # docs/plans/kanban-markdown-labels.md for the mmdc measurements this
    # subset is drawn from.
    #
    # Parsing is delegated to `kramdown` (see the private `Parser` below)
    # rather than hand-rolled: mermaid itself runs a real markdown lexer
    # (`marked`) over label text rather than scanning characters, and a
    # hand-rolled scanner got bold/italic nesting, triple markers and
    # break-spanning emphasis wrong in ways a real parser doesn't. `Parser`
    # restricts kramdown to exactly the block/span parsers this subset
    # needs (`:paragraph`/`:blank_line` and `:emphasis` — nothing else) so
    # kramdown's own HTML, smart-quote, codespan, footnote, table, header
    # and list handling never fires; whatever isn't bold/italic markup
    # comes back as literal text, character for character, matching mmdc.
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

      # kramdown's `:emphasis` parser backtracks: a marker that fails to
      # find a well-flanked close re-scans the remainder of the text before
      # falling back to literal text, and that re-scan can itself contain
      # more failing markers. Measured directly against `Parser` (bypassing
      # this module's own code, to confirm the cost is kramdown's): `"**a "
      # * 75` (300 attacker-controlled chars of ambiguous bold markers)
      # takes ~170ms, `"**a " * 500` (2,000 chars) takes ~44s — worse than
      # quadratic, and worse than the Unicode `String#[]` blowup this
      # rewrite exists to fix. A kanban card's text is diagram source an
      # attacker can shape, so this has to stay bounded regardless of what
      # markers it contains; no real card or column label is anywhere near
      # this long. `parse_lines` falls back to unstyled literal lines
      # rather than calling kramdown past this length.
      MAX_PARSEABLE_LENGTH = 200

      module_function

      # Splits text on hard line breaks and parses each line's markup.
      #
      # The whole text is parsed as one kramdown document rather than
      # split-then-parsed line by line: kramdown keeps a `\n` that isn't
      # preceded by a blank line embedded, literally, inside whatever span
      # it falls in (including inside an open bold/italic run), so a break
      # inside `**a\nb**` stays part of one bold span instead of being cut
      # into two independently-parsed halves that can't see each other's
      # marker state. `split_on_hard_breaks` below is what turns those
      # embedded `\n`s (and the blank-line gaps between kramdown's
      # top-level blocks) into the line-array shape callers expect.
      #
      # @param text [String] raw label text, possibly containing `**`/`*`
      #   markers and literal newlines
      # @return [Array<Array<Run>>] one run array per line
      def parse_lines(text)
        raw = text.to_s
        return [[]] if raw.empty?
        return literal_lines(raw) if raw.length > MAX_PARSEABLE_LENGTH

        root, = Parser.parse(raw)
        lines = []

        root.children.each do |block|
          case block.type
          when :p
            lines.concat(split_on_hard_breaks(flatten_runs(block, bold: false, italic: false)))
          when :blank
            block.value.count("\n").times { lines << [] }
          else
            raise "unexpected kramdown block #{block.type.inspect} in a markdown label"
          end
        end

        lines
      end

      # The `MAX_PARSEABLE_LENGTH` fallback: every literal `\n`-delimited
      # line becomes one unstyled run, with no markup parsing at all — the
      # same line-splitting a label this long would get either way, minus
      # the bold/italic detection that isn't worth kramdown's worst case
      # for text no real board is going to have this much of.
      #
      # @api private
      def literal_lines(raw)
        raw.split("\n", -1).map do |line|
          line.empty? ? [] : [Run.new(text: line, bold: false, italic: false)]
        end
      end

      # Walks one `:p` block's children into a flat run list: nesting is
      # represented by the returned runs' bold/italic flags, not by any
      # tree structure the caller has to walk. A run's `text` may still
      # contain an embedded `\n` at this point — `split_on_hard_breaks`
      # resolves that afterward, once the whole block's styling has been
      # flattened out.
      #
      # @api private
      def flatten_runs(node, bold:, italic:)
        node.children.flat_map do |child|
          case child.type
          when :text
            [Run.new(text: child.value, bold: bold, italic: italic)]
          when :strong
            flatten_runs(child, bold: true, italic: italic)
          when :em
            flatten_runs(child, bold: bold, italic: true)
          else
            raise "unexpected kramdown span #{child.type.inspect} in a markdown label"
          end
        end
      end

      # Splits a flat run list on embedded `\n`s into line arrays, keeping
      # each half's bold/italic flags — so a run that broke mid-span still
      # carries its styling on both sides of the break.
      #
      # @api private
      def split_on_hard_breaks(runs)
        lines = [[]]

        runs.each do |run|
          run.text.split("\n", -1).each_with_index do |part, index|
            lines << [] if index.positive?
            lines.last << run.with(text: part) unless part.empty?
          end
        end

        lines
      end

      # `kramdown`, restricted to exactly the block and span parsers this
      # subset needs. Subclassing and reassigning `@block_parsers` /
      # `@span_parsers` is kramdown's own documented extension point (see
      # `Kramdown::Parser::Kramdown`'s class comment) rather than a
      # private-API reach, and it's cheaper than post-filtering a tree that
      # may have already thrown styling information away before we get to
      # see it — e.g. left with the default span parsers, `<b>` inside
      # `**<b>&"x**` swallows what would otherwise be the bold run's
      # closing `**` (no `strong` node is ever produced), and a straight
      # `"` gets turned into a smart-quote element instead of staying
      # literal.
      #
      # @api private
      class Parser < ::Kramdown::Parser::Kramdown
        def initialize(source, options)
          super
          @block_parsers = [:blank_line, :paragraph]
          @span_parsers = [:emphasis]
        end
      end
      private_constant :Parser

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
      # A blank line (`parse_lines` splitting on two adjacent `\n`s)
      # produces an empty runs array, so it has no run to carry its own
      # `dy`. Its line-height is carried forward as `pending_lines` and
      # folded into the next line's leading shift instead of being
      # dropped — two blank lines in a row shift the following line down
      # by three line-heights (`2.4em` waiting plus its own `1.2em`), not
      # one.
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
        pending_lines = 0

        lines.each_with_index.flat_map do |runs, line_index|
          pending_lines += 1 if line_index.positive?

          runs.each_with_index.map do |run, run_index|
            new_line = run_index.zero? && pending_lines.positive?

            Svg::Tspan.new.tap do |t|
              if new_line
                t.x = x
                t.dy = line_height_dy(pending_lines)
                pending_lines = 0
              end
              t.font_weight = "bold" if run.bold || base_font_weight == "bold"
              t.font_style = "italic" if run.italic
              t.content = run.text
            end
          end
        end
      end

      # `line_count * 1.2em`, computed in tenths rather than `Float`
      # multiplication: `3 * 1.2` is `3.5999999999999996` in binary
      # floating point, which would put a wrong `dy` in the SVG.
      #
      # @param line_count [Integer] number of accumulated line-heights
      # @return [String]
      # @api private
      def line_height_dy(line_count)
        tenths = line_count * 12
        "#{tenths / 10}.#{tenths % 10}em"
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
      # The 3-character ellipsis cost is reserved against `budget` up
      # front, once — not against whatever's left of `remaining` when the
      # overflowing run happens to be reached. Reserving it per-run instead
      # undercounts: several already-kept runs can each consume part of
      # `remaining` without ever needing the reservation themselves, so by
      # the time the overflowing run pays it, the total visible length
      # (kept runs + this run's cut + "...") comes out over `budget`.
      #
      # @param runs [Array<Run>]
      # @param budget [Integer] visible characters available, ellipsis
      #   included
      # @return [Array<Run>]
      # @api private
      def truncate_line(runs, budget)
        remaining = [budget - 3, 0].max
        kept = []

        runs.each do |run|
          if run.text.length <= remaining
            kept << run
            remaining -= run.text.length
          else
            kept << run.with(text: "#{run.text[0, remaining]}...")
            break
          end
        end

        kept
      end
    end
  end
end
