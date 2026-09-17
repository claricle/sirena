# frozen_string_literal: true

require "kramdown"
require_relative "../svg/tspan"
require_relative "markdown_text/emphasis_simulator"

module Sirena
  module Renderer
    # Parses mermaid's markdown subset used inside diagram label text: bold
    # (`**text**`), italic (`*text*`, nestable in either order, including
    # `***both***`), a backslash-escaped marker staying literal, and a
    # literal newline as a hard line break — even inside an open bold or
    # italic run. Nothing else: no code spans, links, headers or lists.
    # Parsing is delegated to `kramdown` (see the private `Parser` below),
    # restricted to exactly `:paragraph`/`:blank_line` and
    # `:emphasis`/`:escaped_chars` — anything else stays literal.
    # Callers only need `parse_lines` plus `assign_markdown_text`
    # (optionally through `truncate_runs` first); the rest are private
    # helpers between them.
    module MarkdownText
      # One styled run of text. `bold` and `italic` are independent booleans
      # rather than a single "style" enum because nesting (`**bold *and
      # italic* end**`) produces a run that is both at once.
      Run = Data.define(:text, :bold, :italic)

      # A run of text with neither `*` nor `_` can never come back styled
      # (`Parser`'s only span parsers are `:emphasis`/`:escaped_chars`), so
      # `parse_lines` skips kramdown entirely for such text below.
      #
      # kramdown's `:emphasis` parser backtracks on a marker that fails to
      # find a well-flanked close, and the backtracking cost is driven by
      # how many `*`/`_` characters are packed TOGETHER, not by the label's
      # total length. Do not swap this back to a length-based cap: an
      # ordinary long label with one bold word costs nothing, while a short
      # label packed with markers is the expensive case this bounds. See
      # this constant's spec for the measured cost curve.
      MAX_EMPHASIS_MARKERS = 30

      # A backstop independent of `MAX_EMPHASIS_MARKERS` above, for parse
      # tree size rather than backtracking cost: kramdown's per-character
      # cost is linear once marker density is low, so this only keeps one
      # label from building an arbitrarily large AST.
      MAX_PARSEABLE_LENGTH = 10_000

      # The only two characters that can ever start an `:emphasis` span
      # under `Parser` (see `MAX_EMPHASIS_MARKERS` above) — matches
      # kramdown's own `Emphasis::EMPHASIS_START`. `\` (the
      # `:escaped_chars` trigger) doesn't need its own check here: text
      # with a backslash but no `*`/`_` has nothing an escape could ever
      # act on differently from plain literal text.
      EMPHASIS_MARKER = /[*_]/

      # The only two block types `parse_lines` knows how to walk — anything
      # else in the parsed tree means the whole label falls back to
      # `literal_lines`. See the `root.children.any?` guard in `parse_lines`.
      PLAIN_BLOCK_TYPES = [:p, :blank].freeze

      # The visible-character budget `Renderer::Kanban#render_card_text`
      # truncates a card's parsed lines to (via `truncate_runs`). Shared
      # here, not kept private on `Renderer::Kanban`, because
      # `Transform::Kanban#calculate_card_height` needs the exact same
      # budget: sizing from the raw text's newline count instead of this
      # module's own truncated line count diverges once a card crosses the
      # budget, since the renderer silently drops the excess lines.
      CARD_TEXT_CHAR_BUDGET = 25

      module_function

      # Splits text on hard line breaks and parses each line's markup.
      #
      # The whole text is parsed as one kramdown document rather than
      # split-then-parsed line by line: kramdown keeps an embedded `\n`
      # (one not preceded by a blank line) literally inside whatever span
      # it falls in, including an open bold/italic run, so a break inside
      # `**a\nb**` stays part of one bold span. `split_on_hard_breaks`
      # below turns those embedded `\n`s (and the blank-line gaps between
      # kramdown's top-level blocks) into the line-array shape callers
      # expect.
      #
      # @param text [String] raw label text, possibly containing `**`/`*`
      #   markers and literal newlines
      # @return [Array<Array<Run>>] one run array per line
      def parse_lines(text)
        raw = text.to_s
        raw = raw.scrub unless raw.valid_encoding?
        return [[]] if raw.empty?
        return literal_lines(raw) unless raw.match?(EMPHASIS_MARKER)
        return literal_lines(raw) if raw.length > MAX_PARSEABLE_LENGTH
        return literal_lines(raw) if real_marker_count(raw) > MAX_EMPHASIS_MARKERS
        return literal_lines(raw) if unsafe_escaped_delimiter_interaction?(raw)
        return literal_lines(raw) if unsafe_delimiter_run_structure?(raw)

        root, = Parser.parse(raw)

        # A line led by a tab or 4+ spaces (kramdown's own `:codeblock`
        # parser, excluded from `Parser`'s `@block_parsers`) matches
        # neither `:paragraph` nor `:blank_line`, so kramdown's fallback
        # line-scanning appends a bare `:text` block directly under root
        # instead of wrapping it in `:p` — and a stray marker elsewhere in
        # the same text fragments that block off from its `:p` siblings,
        # producing several independent literal lines where mermaid
        # renders one.
        #
        # No construct this restricted `Parser` can produce should crash
        # or corrupt the renderer, matching mermaid's own "unsupported
        # construct -> literal passthrough" behavior — so the moment any
        # unexpected block type shows up ANYWHERE in the tree, the whole
        # label falls back to `literal_lines` on the raw text, untouched
        # by kramdown. That guarantees no fragmentation and no marker loss
        # by construction, at the cost of losing styling entirely for that
        # one label — the same trade-off already accepted above.
        return literal_lines(raw) if root.children.any? { |block| !PLAIN_BLOCK_TYPES.include?(block.type) }
        return literal_lines(raw) if unsafe_emphasis_divergence?(raw, root)

        lines = []

        root.children.each do |block|
          case block.type
          when :p
            lines.concat(split_on_hard_breaks(flatten_runs(block, bold: false, italic: false)))
          when :blank
            # Real mmdc's CSS sets paragraph margins to zero, so any number
            # of blank lines between two `:p` blocks (or a leading/trailing
            # one) renders with NO extra vertical space — do not push a
            # line per blank-line `\n` here. A `:blank` block stays in
            # `PLAIN_BLOCK_TYPES` (so its presence doesn't trip the
            # fallback-to-literal guard above) but contributes zero lines.
          end
        end

        lines
      end

      # The `MAX_EMPHASIS_MARKERS`/`MAX_PARSEABLE_LENGTH` fallback — and,
      # since `parse_lines` only reaches the kramdown `Parser` when `raw`
      # contains a `*`/`_` at all, this is also the path ordinary
      # marker-free card text takes: every literal `\n`-delimited line
      # becomes one unstyled run, no markup parsing at all.
      #
      # Paragraphs (text separated by 2+ consecutive `\n`s) are split out
      # first and concatenated with no separator lines between them,
      # matching real mmdc's zero-margin paragraph CSS — do not split on
      # every single `\n` without that distinction, or a blank-line gap
      # produces a spurious empty line. Only a genuine single `\n` inside
      # one paragraph still produces a per-line split (a real hard break).
      #
      # @api private
      def literal_lines(raw)
        raw.split(/\n{2,}/, -1).flat_map do |paragraph|
          next [] if paragraph.empty?

          paragraph.split("\n", -1).map do |line|
            line.empty? ? [] : [Run.new(text: line, bold: false, italic: false)]
          end
        end
      end

      # Counts only the `*`/`_` markers that can actually reach
      # `:emphasis` — a backslash-escaped marker is consumed by
      # `:escaped_chars` as one cheap, fixed-cost substitution before
      # `:emphasis` ever sees it, so it can never touch the backtracking
      # `MAX_EMPHASIS_MARKERS` bounds. Do not count raw `*`/`_` occurrences
      # here, or a label full of escaped markers trips the cap and loses
      # its styling for no reason.
      #
      # Strips exactly the substrings kramdown's own `:escaped_chars` span
      # parser would consume, using kramdown's own `ESCAPED_CHARS` regex
      # rather than a hand-copied pattern, so this can't silently drift
      # from what `Parser` actually escapes on a future kramdown upgrade.
      #
      # @param raw [String]
      # @return [Integer]
      # @api private
      def real_marker_count(raw)
        raw.gsub(::Kramdown::Parser::Kramdown::ESCAPED_CHARS, '').count('*_')
      end

      # True when an escaped marker leaves a lone (length-1) unescaped
      # marker immediately behind it, and that lone marker later meets a
      # same-character run of a DIFFERENT length — typically the run
      # closing an outer bold/italic span. kramdown's emphasis matching and
      # `marked`'s delimiter-run algorithm resolve that length mismatch
      # differently; this label is unrecoverable without risking a WRONG
      # (not just unstyled) render, so it falls back to `literal_lines`.
      #
      # A lone marker is NOT unsafe by itself: an orphan run of length 0
      # (not adjacent to another marker), length 2+ (pairs cleanly with
      # itself), or one whose next same-character run is ALSO length 1 (a
      # clean single-to-single pairing) all already match mmdc unchanged.
      # Only the length-1-meets-mismatched-length shape is unsafe. See this
      # method's spec for the corpus, each pinned against real mmdc.
      #
      # Every escaped-chars match is blanked out with a placeholder
      # character first (not deleted — two real runs either side of an
      # escaped marker must stay separated, not merge into one longer run)
      # so `next_run` can only ever match a REAL, unescaped run.
      #
      # @param raw [String]
      # @return [Boolean]
      # @api private
      def unsafe_escaped_delimiter_interaction?(raw)
        raw.scan(::Kramdown::Parser::Kramdown::ESCAPED_CHARS) do
          marker = ::Regexp.last_match(1)
          next unless %w[* _].include?(marker)

          after = raw[::Regexp.last_match.end(0)..]
          orphan_run = after[/\A#{Regexp.escape(marker)}+/]
          next unless orphan_run&.length == 1

          search_region = after[orphan_run.length..]
            .gsub(::Kramdown::Parser::Kramdown::ESCAPED_CHARS, " ")
          next_run = search_region[/#{Regexp.escape(marker)}+/]
          return true if next_run && next_run.length != 1
        end

        false
      end

      # kramdown's emphasis grammar is not `marked`'s CommonMark-style
      # delimiter-run algorithm, and the two disagree on some valid short
      # labels. Rather than reimplement CommonMark's delimiter-run/flanking
      # rules in full, this extends the same literal-fallback safety net:
      # detect the specific unsafe delimiter-run SHAPES below and fall back
      # to `literal_lines`, safe-but-unstyled rather than wrong-but-styled.
      #
      # Two independent shapes, either of which is unsafe (a third, general
      # check — comparing the real parse against `EmphasisSimulator`'s
      # prediction of what `marked` would produce — runs later in
      # `parse_lines`; see `unsafe_emphasis_divergence?`):
      #
      # A) A maximal run of 4+ of the same marker character: kramdown's
      #    `Emphasis::EMPHASIS_START` only ever recognizes a 1- or
      #    2-character token per match, with no native handling for a run
      #    this long (it does special-case length 3, `***both***`).
      #
      # C) A single (length-1) run of one marker character immediately
      #    NESTED with a single run of the OTHER marker character, closes
      #    mirroring the nesting (`_*...*_` or `*_..._*`) — deliberately
      #    narrower than "any adjacency": a SEQUENTIAL pair (one span
      #    closing immediately before the next opens, e.g. `*a*_b_`) is
      #    NOT this shape and must stay safe. Only the NESTED wrap is
      #    unsafe.
      #
      # A run-length-only check with no flanking context is unsound here —
      # `"**a*a**"` and `"**foo* bar**"` share the same `*`-run shape but
      # only one is unsafe. Don't reintroduce one; `unsafe_emphasis_divergence?`
      # below replaces it. Not a general proof this matches `marked` for
      # every delimiter combination — see this method's spec for the
      # measured corpus, both unsafe and safe shapes.
      #
      # @param raw [String]
      # @return [Boolean]
      # @api private
      def unsafe_delimiter_run_structure?(raw)
        blanked = raw.gsub(::Kramdown::Parser::Kramdown::ESCAPED_CHARS, " ")

        return true if blanked.scan(/\*+|_+/).any? { |run| run.length >= 4 }

        nested_delimiter_wrap?(blanked)
      end

      # Guard C above: a single `_` immediately opening a single `*` (or the
      # reverse), with the matching closes mirroring the nesting later in
      # the string — as opposed to one span's close immediately followed by
      # the next span's open (sequential, safe).
      #
      # @param blanked [String]
      # @return [Boolean]
      # @api private
      def nested_delimiter_wrap?(blanked)
        blanked.match?(/(?<!_)_(?!_)\*(?!\*).*?(?<!\*)\*(?!\*)(?<!_)_(?!_)/) ||
          blanked.match?(/(?<!\*)\*(?!\*)_(?!_).*?(?<!_)_(?!_)(?<!\*)\*(?!\*)/)
      end

      # Predicts what real `marked` would produce per paragraph (via
      # `EmphasisSimulator`) and compares it to kramdown's actual parse;
      # falls back to `literal_lines` on any divergence. Requires
      # `parse_lines`'s earlier non-`:p`/non-`:blank` guard already in
      # place (paragraphs are matched to `:p` blocks positionally). Strips
      # each paragraph first, matching kramdown's own block-level trim.
      #
      # @param raw [String]
      # @param root [Kramdown::Element] the parsed root, from `Parser.parse`
      # @return [Boolean]
      # @api private
      def unsafe_emphasis_divergence?(raw, root)
        paragraphs = raw.split(/\n{2,}/, -1).reject(&:empty?)
        p_blocks = root.children.select { |block| block.type == :p }
        return true if paragraphs.length != p_blocks.length

        paragraphs.zip(p_blocks).any? do |paragraph, block|
          kramdown_runs = EmphasisSimulator.coalesce_runs(flatten_runs(block, bold: false, italic: false))
          kramdown_runs != EmphasisSimulator.simulate(paragraph.strip)
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
            # Not reachable through this restricted `Parser` today — kept
            # as a symmetric guard against a future kramdown release adding
            # a span node type this method doesn't handle. Degrades to
            # literal text under whichever bold/italic context was already
            # active, rather than crashing.
            [Run.new(text: literal_text_of(child), bold: bold, italic: italic)]
          end
        end
      end

      # Extracts a node's literal text regardless of shape: a leaf node
      # (kramdown's own `:text`, or the fallback `:text` block
      # `parse_lines`'s `else` produces for a line no active block parser
      # claims) carries it directly as `value`; a structural node with none
      # carries it on its children instead, so recurse into those.
      #
      # @api private
      def literal_text_of(node)
        return node.value if node.value.is_a?(String)

        node.children.map { |child| literal_text_of(child) }.join
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
      # `@span_parsers` is kramdown's own documented extension point rather
      # than a private-API reach, and it's cheaper than post-filtering a
      # tree that may have already thrown styling information away —
      # e.g. with the default span parsers, `<b>` inside `**<b>&"x**`
      # swallows what would otherwise be the bold run's closing `**`.
      #
      # `:escaped_chars` (kramdown's `\X` -> literal `X` rule) sits
      # alongside `:emphasis` rather than being left out: without it,
      # `\*escaped*` came back with "escaped" wrongly italicized, since a
      # bare backslash passes through as literal text while the `*...*` on
      # either side of it still pairs up as a real emphasis span.
      #
      # @api private
      class Parser < ::Kramdown::Parser::Kramdown
        def initialize(source, options)
          super
          @block_parsers = [:blank_line, :paragraph]
          @span_parsers = [:emphasis, :escaped_chars]
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
      # `pending_lines` is kept as an accumulating counter, not a per-line
      # constant, in case a future producer of `lines` ever passes an empty
      # runs array for a line (neither current producer does).
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
