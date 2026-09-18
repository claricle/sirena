# frozen_string_literal: true

require "kramdown"
require_relative "markdown_text/emphasis_simulator"

module Sirena
  # Parses mermaid's markdown subset used inside diagram label text: bold,
  # italic (nestable either order, including `***both***`), a
  # backslash-escaped marker staying literal, and a literal newline as a
  # hard line break — even inside an open bold/italic run. Nothing else.
  # Delegates to `kramdown` (private `Parser` below), restricted to
  # `:paragraph`/`:blank_line` and `:emphasis`/`:escaped_chars` only.
  #
  # Layer-neutral (no SVG/XML): shared by `Transform::Kanban` (sizing) and
  # `Renderer::MarkdownText` (rendering), so `transform/` never has to
  # require anything under `renderer/`.
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

    # The visible-character budget both `Renderer::Kanban#render_card_text`
    # (via `Renderer::MarkdownText`) and `Transform::Kanban#rendered_line_count`
    # truncate a card's parsed lines to (via `truncate_runs`). Shared here
    # so the two layers can never drift: sizing from the raw text's newline
    # count instead of this module's own truncated line count diverges once
    # a card crosses the budget, since the renderer silently drops the
    # excess lines.
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
      raw = transcode_binary_to_utf8(raw) if raw.encoding == Encoding::ASCII_8BIT
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

    # `ASCII-8BIT` always reports `valid_encoding? == true`, so the
    # `raw.scrub unless raw.valid_encoding?` guard below never fires for
    # it and kramdown's own `String#encode` raises
    # `Encoding::UndefinedConversionError` on a non-ASCII byte instead.
    # Do not widen this past ASCII-8BIT: other encodings (e.g.
    # ISO-8859-1) report `valid_encoding?` meaningfully already.
    #
    # @param raw [String]
    # @return [String]
    # @api private
    def transcode_binary_to_utf8(raw)
      raw.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
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
    # short labels. Falls back to `literal_lines` for two unsafe
    # delimiter-run SHAPES (a third, general check runs later; see
    # `unsafe_emphasis_divergence?`): A) 4+ of the same marker character
    # in a row, C) a NESTED length-1 wrap of both markers (`_*...*_`,
    # not a SEQUENTIAL `*a*_b_`, which must stay safe).
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

    # Truncates markdown-parsed lines to at most `max_length` visible
    # (post-markup) characters, cutting on run boundaries rather than
    # mid-marker. A run within the FIRST line may be cut partway through
    # with "..." appended; a later line (one that only exists because of
    # a hard line break) is kept whole or dropped whole, never cut
    # partway through.
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
    # against `budget` up front, once — reserving it per-run instead
    # undercounts, letting the total come out over `budget`.
    #
    # @param runs [Array<Run>]
    # @param budget [Integer] visible characters, ellipsis included
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
