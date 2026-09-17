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
      # Parsed as one kramdown document, not split then parsed line by
      # line: kramdown keeps an embedded `\n` literally inside whatever
      # span it falls in (including an open bold/italic run), so
      # `**a\nb**` stays one bold span. `split_on_hard_breaks` turns those
      # embedded breaks into the line-array shape callers expect.
      #
      # @param text [String] raw label text, markers and literal newlines
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

        # A line led by a tab or 4+ spaces matches neither `:paragraph`
        # nor `:blank_line` in this restricted `Parser`, so kramdown's own
        # fallback appends a bare `:text` block under root instead of
        # wrapping it in `:p` — fragmenting a label that also has a stray
        # marker elsewhere into several literal lines where mermaid
        # renders one. So the moment ANY unexpected block type shows up
        # anywhere in the tree, the whole label falls back to
        # `literal_lines` on the raw text, untouched by kramdown —
        # guaranteeing no fragmentation or marker loss, at the cost of
        # losing styling for that one label.
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

      # The `MAX_EMPHASIS_MARKERS`/`MAX_PARSEABLE_LENGTH` fallback, and
      # also the path ordinary marker-free text takes: every literal
      # `\n`-delimited line becomes one unstyled run. Paragraphs (2+
      # consecutive `\n`s) are split out first and concatenated with no
      # separator lines, matching mmdc's zero-margin paragraph CSS — do
      # not split on every `\n` without that distinction, or a blank-line
      # gap produces a spurious empty line.
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

      # Counts only the `*`/`_` markers that can reach `:emphasis`: an
      # escaped marker is consumed by `:escaped_chars` first as one
      # fixed-cost substitution, so it never touches the backtracking
      # `MAX_EMPHASIS_MARKERS` bounds. Do not count raw `*`/`_`
      # occurrences, or an escaped-heavy label trips the cap for nothing.
      # Strips exactly what kramdown's `ESCAPED_CHARS` regex would
      # consume, so this can't drift from `Parser` on a kramdown upgrade.
      #
      # @param raw [String]
      # @return [Integer]
      # @api private
      def real_marker_count(raw)
        raw.gsub(::Kramdown::Parser::Kramdown::ESCAPED_CHARS, '').count('*_')
      end

      # True when an escaped marker leaves a lone (length-1) unescaped
      # marker behind it, later meeting a same-character run of a
      # DIFFERENT length — kramdown and `marked` resolve that mismatch
      # differently, risking a WRONG render, so this falls back to
      # `literal_lines`. See this method's spec for the pinned corpus of
      # unsafe vs. safe shapes. Escaped-chars matches are blanked with a
      # placeholder (not deleted) so `next_run` can only match a REAL run.
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

      # kramdown's emphasis grammar disagrees with `marked`'s on some valid
      # short labels. Detects two unsafe delimiter-run SHAPES and falls
      # back to `literal_lines` for them (a third, general check runs
      # later; see `unsafe_emphasis_divergence?`): A) a maximal run of 4+
      # of the same marker character, C) a length-1 run of one marker
      # NESTED with a length-1 run of the other (`_*...*_`), as opposed to
      # a SEQUENTIAL pair (`*a*_b_`), which must stay safe. A run-length
      # check with no flanking context is unsound: see this method's spec.
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
      # subset needs (documented extension point: subclassing and
      # reassigning `@block_parsers`/`@span_parsers`). `:escaped_chars`
      # sits alongside `:emphasis` rather than being left out — without it
      # a bare backslash passes through as literal text while the `*...*`
      # on either side of it still pairs up as a real emphasis span,
      # wrongly italicizing an escaped marker's surrounding text.
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
      # A label with no markup and no hard line break parses down to the
      # original string in one unstyled run, and keeps setting plain
      # `content` — no `<tspan>` wrapper, same XML shape every existing
      # fixture and REXML `.text` check already expects. Only a label that
      # needs per-run styling or a line break pays for `<tspan>` children.
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
      # Every run after a line's first continues immediately after the
      # previous run — no `x`/`dy` needed. Only the FIRST run of a line
      # that followed a hard line break needs both: `x` to reset to the
      # label's left edge (or center), and `dy` to move down one line
      # height. The very first line needs neither. `pending_lines` is an
      # accumulating counter, not a per-line constant, in case a future
      # producer of `lines` ever passes an empty runs array for a line.
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
      # crosses the boundary. The 3-character ellipsis cost is reserved
      # against `budget` up front, once — not per-run when the overflowing
      # run is reached, which undercounts: kept runs would each consume
      # `remaining` without paying the reservation, pushing the final
      # total (kept + cut run + "...") over `budget`.
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
