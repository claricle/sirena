# frozen_string_literal: true

require "kramdown"
require_relative "../svg/tspan"

module Sirena
  module Renderer
    # Parses mermaid's markdown subset used inside diagram label text: bold
    # (`**text**`), italic (`*text*`, nestable with bold, in either order,
    # including `***both***`), a backslash-escaped marker staying literal
    # (`\*not italic*`), and a literal newline as a hard line break —
    # including one embedded inside a bold/italic run, which keeps that
    # run's styling on both sides of the break. Nothing else — no code
    # spans, links, headers or lists; mermaid's own rendering of these
    # labels doesn't support more than this. Every claim above is pinned by
    # an mmdc-verified spec in this file's spec, cited inline where it
    # matters (see `MAX_EMPHASIS_MARKERS` and `Parser` below for the two
    # places mermaid's actual behavior shaped a non-obvious choice here).
    #
    # Parsing is delegated to `kramdown` (see the private `Parser` below)
    # rather than hand-rolled: mermaid itself runs a real markdown lexer
    # (`marked`) over label text rather than scanning characters, and a
    # hand-rolled scanner got bold/italic nesting, triple markers and
    # break-spanning emphasis wrong in ways a real parser doesn't. `Parser`
    # restricts kramdown to exactly the block/span parsers this subset
    # needs (`:paragraph`/`:blank_line`, `:emphasis` and `:escaped_chars` —
    # nothing else) so kramdown's own HTML, smart-quote, codespan,
    # footnote, table, header and list handling never fires; whatever
    # isn't bold/italic markup or an escaped marker comes back as literal
    # text, character for character, matching mmdc.
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

      # A run of text with neither `*` nor `_` can never come back styled:
      # `Parser`'s only active span parsers are `:emphasis` and
      # `:escaped_chars`, and kramdown's own `EMPHASIS_START`
      # (`Kramdown::Parser::Kramdown::Emphasis`) is `/(?:\*\*?|__?)/` —
      # those two characters are the only way `:emphasis` ever fires, and
      # `:escaped_chars` only fires on a literal backslash. Verified
      # directly against `Parser`: entities, raw HTML and smart quotes all
      # come back as plain `:text` regardless of length. So `parse_lines`
      # skips kramdown entirely for such text (see the `raw.match?` guard
      # below) — a markdown-free diagram (the overwhelming majority) pays
      # zero parse cost per label regardless of how many cards it has.
      #
      # kramdown's `:emphasis` parser backtracks: a marker that fails to
      # find a well-flanked close re-scans the remainder of the text before
      # falling back to literal text, and that re-scan can itself contain
      # more failing markers. This used to be bounded by capping raw
      # LENGTH (`raw.length > 50`), but that bounds the wrong quantity: an
      # entirely ordinary label can cross a length cap while carrying no
      # backtracking risk at all — verified directly, `"Please review the
      # **proposed** deployment plan asap and get back to the team before
      # the end of the day tomorrow"` is 111 characters with exactly one
      # bold word (4 `*` characters total) and costs ~0.2ms to parse, yet
      # a 50-character length cap would have rejected it and printed the
      # `**` markers literally.
      #
      # The actual cost driver is how many `*`/`_` characters are packed
      # together, not the label's total length — measured directly against
      # `Parser` (bypassing this module's own code): a fixed small marker
      # count stays fast even at enormous surrounding length (30 markers
      # spread across 3,000,000 filler characters costs ~59ms; 10 markers
      # across 1,000,000 costs ~17.5ms), while packing markers adjacent to
      # each other is what gets expensive — confirming `_` counts too
      # (kramdown's emphasis grammar treats `*` and `_` as interchangeable
      # markers), the worst pattern found is `"**_a " * n` (mixing both
      # marker characters so each `_` reopens kramdown's backtracking on
      # the immediately preceding failed `**`; four other marker-density
      # shapes tried at the same marker counts, `"**a "`, `"**__a "`,
      # `"_a*_a* "`, `"*_a "`, all cost less): ~4ms at 30 markers, ~49ms at
      # 60, ~206ms at 90. At 30 markers, a diagram-level worst case — every
      # one of 300 cards holding exactly this pattern, run through
      # `Engine#render` end to end — costs ~1.2s total. A kanban card's
      # text is diagram source an attacker can shape, so whatever reaches
      # kramdown has to stay bounded regardless of what markers it
      # contains — but bounding on marker COUNT rather than raw length
      # leaves any label with only a marker or two untouched, however long.
      MAX_EMPHASIS_MARKERS = 30

      # A backstop independent of `MAX_EMPHASIS_MARKERS` above: kramdown's
      # per-character parse cost is linear once marker density is low
      # (measured up to 3,000,000 characters above), so this exists only
      # to keep one label from building an arbitrarily large AST rather
      # than to guard against backtracking — no real kanban card or column
      # title approaches this length regardless of markup.
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
      # here rather than kept as a private literal on `Renderer::Kanban`
      # because `Transform::Kanban#calculate_card_height` needs the exact
      # same budget to size a card correctly — sizing from the raw text's
      # newline count instead of this module's own truncated line count
      # diverges once a card has enough lines to cross the budget: the
      # renderer silently drops the excess lines, but a raw count still
      # allocates height for them (Codex round 5 High, reproduced with a
      # 100-line, one-character-per-line card: raw-newline sizing assumes
      # all 100 lines render, the renderer only ever draws lines within
      # this budget).
      CARD_TEXT_CHAR_BUDGET = 25

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
        return literal_lines(raw) unless raw.match?(EMPHASIS_MARKER)
        return literal_lines(raw) if raw.length > MAX_PARSEABLE_LENGTH
        return literal_lines(raw) if real_marker_count(raw) > MAX_EMPHASIS_MARKERS
        return literal_lines(raw) if unsafe_escaped_delimiter_interaction?(raw)
        return literal_lines(raw) if unsafe_delimiter_run_structure?(raw)

        root, = Parser.parse(raw)

        # A line led by a tab or 4+ spaces (kramdown's own `:codeblock`
        # block parser, excluded from `Parser`'s `@block_parsers`) matches
        # neither `:paragraph` nor `:blank_line`, so kramdown's own
        # line-scanning fallback (`Parser::Kramdown#parse_blocks`'s
        # `add_text` branch) appends a bare `:text` block directly under
        # root instead of wrapping it in `:p`. Reconstructing that block's
        # text from the tree fragments it — kramdown still span-parses
        # inside its own fallback, so a stray marker elsewhere in the same
        # text splits the fallback block off from its neighbouring `:p`
        # siblings and produces several independent literal lines where
        # mermaid renders one. `Parser.parse("\t*hello* world")` is exactly
        # this: kramdown emits a `:text` block ("\t"), a `:p` ("hello",
        # `:em`) and a `:text` block (" world") as three siblings, and the
        # per-node literal handling this replaced turned that into three
        # fragmented lines with the `*` markers gone.
        #
        # No construct this restricted `Parser` can produce should crash or
        # corrupt the renderer, matching mermaid's own "unsupported
        # construct -> literal passthrough" behavior — so the moment any
        # unexpected block type shows up ANYWHERE in the tree, the whole
        # label is unrecoverable as styled markdown and falls back to the
        # exact same simple, correct path already used for over-length
        # input: `literal_lines` on the raw text, untouched by kramdown.
        # That guarantees no fragmentation and no marker loss by
        # construction, at the cost of that one label losing styling
        # entirely — the same trade-off already accepted above for
        # `MAX_EMPHASIS_MARKERS`/`MAX_PARSEABLE_LENGTH`.
        return literal_lines(raw) if root.children.any? { |block| !PLAIN_BLOCK_TYPES.include?(block.type) }

        lines = []

        root.children.each do |block|
          case block.type
          when :p
            lines.concat(split_on_hard_breaks(flatten_runs(block, bold: false, italic: false)))
          when :blank
            # Codex round 6 High: this used to push one empty `[]` line per
            # blank-line `\n` in the gap, modeling a paragraph break as
            # extra rendered rows. Real mmdc's CSS sets paragraph margins to
            # zero, so any number of blank lines between two `:p` blocks (or
            # a leading/trailing one, which kramdown also reports as a
            # `:blank` block) renders with NO extra vertical space at all —
            # adjacent `<p>` tags sit exactly like a single plain line
            # break, and a leading/trailing one contributes nothing
            # visible. Verified against real mmdc: `card[A\n\nB]` renders
            # `<p>A</p><p>B</p>` with a normal single-line advance between
            # them, not a doubled gap, and `card[A\n\n]` renders `<p>A</p>`
            # alone with no trailing blank row. So a `:blank` block is
            # walked (it must stay in `PLAIN_BLOCK_TYPES` so its presence
            # doesn't trip the fallback-to-literal guard above) but
            # contributes zero lines, regardless of how many `\n`s it
            # spans.
          end
        end

        lines
      end

      # The `MAX_EMPHASIS_MARKERS`/`MAX_PARSEABLE_LENGTH` fallback — and,
      # since `parse_lines` only reaches the kramdown `Parser` when `raw`
      # contains a `*`/`_` at all, this is also the path ordinary
      # marker-free card text takes: every literal `\n`-delimited line
      # becomes one unstyled run, with no markup parsing at all — the same
      # line-splitting this label would get either way, minus the
      # bold/italic detection that isn't worth kramdown's worst case for
      # text this marker-dense (or, for the length backstop, this long).
      #
      # Codex round 6 High: this used to split on every single `\n`,
      # treating a blank-line paragraph gap the same as a real line — a
      # `\n\n` (or more) run produced one or more empty `[]` lines in the
      # output, same defect as the `:blank` case above and hit by the exact
      # same repro (`card[A\n\n]`, `card[A\n\nB]`) since neither contains a
      # marker and both take this path, not the kramdown one. Paragraphs
      # (text separated by 2+ consecutive `\n`s) are split out first and
      # concatenated with no separator lines between them — matching real
      # mmdc's zero-margin paragraph CSS — and only a genuine single `\n`
      # inside one paragraph still produces a per-line split (a real hard
      # break, `card[A\nB]` renders `<p>A<br />B</p>` in real mmdc, unlike
      # the blank-line case).
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

      # Codex round 4 High: `raw.count('*_')` (the prior implementation of
      # the `MAX_EMPHASIS_MARKERS` guard) counted a backslash-escaped marker
      # the same as a real one, even though `:escaped_chars` consumes an
      # escaped marker as one cheap, fixed-cost substitution before
      # `:emphasis` ever sees it — it can never touch the backtracking
      # `MAX_EMPHASIS_MARKERS` exists to bound (see the cost comment above).
      # Reproduced directly: `parse_lines('\\*' * 31)` used to trip the
      # guard and fall back to `literal_lines`, which keeps every backslash
      # in the output; real mmdc renders 31 bare stars, no backslashes, at
      # negligible cost. Counting only the markers that can actually reach
      # `:emphasis` fixes it: with 31 escaped markers this now returns 0,
      # stays under the cap, and reaches the real `Parser`, where
      # `:escaped_chars` alone produces the correct 31 bare stars.
      #
      # Strips exactly the substrings kramdown's own `:escaped_chars` span
      # parser would consume, using kramdown's own `ESCAPED_CHARS` regex
      # (`Kramdown::Parser::Kramdown::ESCAPED_CHARS`) rather than a
      # hand-copied pattern, so this can't silently drift from what
      # `Parser` actually escapes on a future kramdown upgrade. `String#gsub`
      # matches left to right, non-overlapping — the same order kramdown's
      # own scanner consumes escape pairs in, which matters for a string
      # like `\\\\*` (an escaped backslash immediately followed by a real,
      # countable marker): the first two characters are consumed as one
      # pair, leaving the `*` to be counted, not swallowed by a second,
      # overlapping match starting on the inner backslash.
      #
      # @param raw [String]
      # @return [Integer]
      # @api private
      def real_marker_count(raw)
        raw.gsub(::Kramdown::Parser::Kramdown::ESCAPED_CHARS, '').count('*_')
      end

      # Codex round 4 High: registering `:emphasis` and `:escaped_chars` as
      # independent span parsers doesn't reproduce mermaid's actual
      # escape-vs-emphasis interaction once an escaped marker leaves exactly
      # ONE unescaped marker of the same character immediately behind it
      # (`\\**` leaves a lone `*`) and that lone marker later meets a
      # same-character run of a DIFFERENT length — typically the run closing
      # an outer bold/italic span. `marked`'s delimiter-run flanking
      # algorithm and kramdown's own emphasis matching resolve that length
      # mismatch differently; kramdown here either drops emphasis entirely
      # or merges the lone marker into the wrong span, while `mmdc`
      # fragments it into extra literal/styled spans. Measured directly,
      # four pairs, real mmdc vs this module before this fix (`task1[...]`
      # inside a kanban label):
      #   `**a \\** b**` -> mmdc `<em><em>a *</em> b</em>*`, this module
      #     `<strong>a ** b</strong>` (wrong: one bold run, not fragmented).
      #   `\\**a**` -> mmdc `*<em>a</em>*`, this module `**a**` (wrong: fully
      #     literal, no `<em>` at all).
      #   `__a \\__ b__` -> same shape and same divergence with `_`.
      # A lone marker is NOT unsafe by itself — measured equally directly,
      # three shapes that keep this module unchanged because they already
      # match mmdc: an orphan run of length 0 (escape isn't adjacent to
      # another marker at all: `\\*escaped* text`), length 2+ (the orphan
      # pairs cleanly with itself: `**\\*x\\***` -> mmdc and this module both
      # `<strong>*x*</strong>`), and a lone orphan whose next same-character
      # run is ALSO length 1, i.e. a clean single-to-single pairing with no
      # length mismatch (`a\\**b*` -> mmdc and this module both
      # `a*<em>b</em>`). Only the length-1-meets-mismatched-length shape is
      # unsafe; this label falls back to `literal_lines` for it rather than
      # risk a wrong (not just unstyled) render — the same trade-off already
      # accepted for `MAX_EMPHASIS_MARKERS`/`MAX_PARSEABLE_LENGTH` above.
      #
      # Not a general proof this module now matches `marked`'s emphasis
      # algorithm for every delimiter-length combination — only the shape
      # above is measured, both unsafe and safe. See this method's spec for
      # every pair cited here, each pinned against real mmdc.
      #
      # Codex round 5 High: the `next_run` search below used to scan `after`
      # RAW, so a second escaped marker sitting between the orphan and the
      # real closing run could itself get matched as `next_run` — its
      # captured length (always 1, an escaped marker is always exactly one
      # character) masked the real, differently-sized closing run further
      # on, so this method returned `false` and let an unsafe interaction
      # through unflagged. Reproduced directly: `\**a \* b**` (an escaped
      # `\*` opens, followed by the real orphan `*`, then ANOTHER escaped
      # `\*` sits before the real `**` closer) — before this fix, `next_run`
      # matched that second escaped marker's own `*` (length 1, "safe") and
      # never looked further to find the real `**` (length 2, unsafe);
      # `unsafe_escaped_delimiter_interaction?` returned `false` and
      # `parse_lines` rendered fully literal `**a \* b**`, while real mmdc
      # fragments it (`*<em>a * b</em>*`, verified directly against `marked`
      # above this method's spec). Blanking out every escaped-chars match
      # first (with a single placeholder character, not deleting it — two
      # real runs either side of an escaped marker must stay separated, not
      # merge into one longer run) means `next_run` can only ever match a
      # REAL, unescaped run, the same guarantee `real_marker_count` already
      # relies on for its own escaped-chars handling above.
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

      # Codex round 6 High: kramdown's emphasis grammar is not `marked`'s
      # CommonMark-style delimiter-run algorithm, and the two disagree —
      # observably, on valid short labels — whenever a run of `*`/`_`
      # markers has a structure kramdown's simpler matching can't resolve
      # the way `marked` does. Four cases Codex cited directly, each
      # verified against real `marked` (`marked.parseInline`):
      #   `****foo****`   -> marked bold "foo", no markers; this module bold
      #     `**foo` + plain `**` (wrong: markers leak into output).
      #   `**foo* bar**`  -> marked italic "foo bar", trailing literal `*`;
      #     this module bold `foo* bar` as one run (wrong: no fragmentation).
      #   `_*a*_`         -> marked italic "a", no markers; this module
      #     italic `*a*` (wrong: inner markers rendered as literal text).
      #   `**foo **bar****` -> marked bold "foo bar", no markers; this
      #     module bold `foo **bar` + plain `**` (wrong: markers leak).
      # Rather than reimplement CommonMark's delimiter-run/flanking rules
      # in full (disproportionate to closing 4 observed cases, and this
      # module's whole design already trades full generality for a
      # falls-back-to-literal safety net — see
      # `unsafe_escaped_delimiter_interaction?` above), this extends that
      # same safety net: detect the specific unsafe delimiter-run SHAPES
      # below and fall back to `literal_lines` for them, safe-but-unstyled
      # rather than wrong-but-styled.
      #
      # Three independent shapes, any one of which is unsafe:
      #
      # A) A maximal run of 4 or more of the same marker character.
      #    Kramdown's `Emphasis::EMPHASIS_START` (`/(?:\*\*?|__?)/`) only
      #    ever recognizes a 1- or 2-character token per match attempt, so
      #    it has no native way to treat a 4+ run as one atomic delimiter
      #    the way it specially handles a length-3 run (`***both***`).
      #    Catches `****foo****`, `*****foo*****`, and the trailing 4-run
      #    in `**foo **bar****`.
      #
      # B) A same-character run-length sequence that doesn't resolve
      #    cleanly under kramdown's own matching rule: exact-length LIFO
      #    closing, OR kramdown's length-3-closes-a-1-and-a-2 combined
      #    match (the same mechanism `***both***` relies on, generalized to
      #    two SEPARATE runs summing to 3, e.g. `*a **b***`) — applied per
      #    character (`*` and `_` independently), walked as a stack. A
      #    naive "every length appears an even number of times" check was
      #    tried first and rejected: it both false-positives on already-safe
      #    shapes (`*a **b***`, `**a**b**`, `_a_b_`, ...) and can't express
      #    the length-3 combined close without a special case anyway.
      #    Safe iff the full run sequence resolves to an empty stack, or
      #    resolves to exactly one unmatched trailing run whose own removal
      #    leaves everything before it empty (i.e. only the very last run in
      #    the sequence is left dangling — kramdown treats a genuinely
      #    unmatched trailing marker as literal text, which IS what `marked`
      #    does too, so a single dangling trailing run is not itself unsafe).
      #    Catches `**foo* bar**` (`*`-runs `[2,1,1]`: dropping the last run
      #    leaves `[2,1]`, which does not resolve — unsafe) and
      #    `**foo **bar****` (`*`-runs `[2,2,4]`, also caught independently
      #    by Guard A above).
      #
      # C) A single (length-1) run of one marker character immediately
      #    (zero-width) NESTED with a single run of the OTHER marker
      #    character — one opens immediately inside the other's open, and
      #    the matching closes mirror it (`_*...*_` or `*_..._*`). Guard B
      #    alone can't see this: each character's OWN run sequence resolves
      #    cleanly in isolation (`_*a*_`'s `_`-runs `[1,1]` and `*`-runs
      #    `[1,1]` each resolve on their own), but kramdown still matches
      #    the wrong pair of delimiters across the two characters. This is
      #    deliberately narrower than "any `*`/`_` adjacency": a SEQUENTIAL
      #    pair — one span closing immediately before the next one opens,
      #    e.g. `*a*_b_` or `_a_*b*` — is NOT this shape and must stay safe
      #    (both already match `marked` exactly; verified directly, and
      #    caught as a false positive by an earlier, cruder adjacency-only
      #    version of this guard during development). Only the NESTED wrap
      #    is unsafe.
      #
      # Not a general proof this module now matches `marked`'s emphasis
      # algorithm for every delimiter-length combination — same disclosure
      # as `unsafe_escaped_delimiter_interaction?` above. Only the shapes
      # above are measured, both unsafe and safe; see this method's spec for
      # the corpus, each pinned against real `marked`.
      #
      # @param raw [String]
      # @return [Boolean]
      # @api private
      def unsafe_delimiter_run_structure?(raw)
        blanked = raw.gsub(::Kramdown::Parser::Kramdown::ESCAPED_CHARS, " ")

        return true if blanked.scan(/\*+|_+/).any? { |run| run.length >= 4 }
        return true if %w[* _].any? { |char| unsafe_character_run_sequence?(blanked, char) }

        nested_delimiter_wrap?(blanked)
      end

      # The per-character stack walk for Guard B above: exact-length LIFO
      # closing, plus kramdown's own length-3-combined close generalized to
      # two separate runs.
      #
      # @param blanked [String] `raw` with every escaped-marker match
      #   replaced by a same-length run of spaces
      # @param char [String] `"*"` or `"_"`
      # @return [Boolean]
      # @api private
      def unsafe_character_run_sequence?(blanked, char)
        runs = blanked.scan(/#{::Regexp.escape(char)}+/).map(&:length)
        !character_runs_resolve_cleanly?(runs)
      end

      # @param runs [Array<Integer>] one maximal run's length per element,
      #   in source order, for a single marker character
      # @return [Boolean]
      # @api private
      def character_runs_resolve_cleanly?(runs)
        stack = []
        runs.each do |len|
          if stack.last == len
            stack.pop
          elsif stack.size >= 2 && stack[-2..].sum == len
            stack.pop(2)
          else
            stack.push(len)
          end
        end

        return true if stack.empty?
        return false unless stack.size == 1

        character_runs_resolve_cleanly?(runs[0..-2])
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
            # Not reachable through this restricted `Parser` today (verified:
            # escapes, entities, raw HTML and smart quotes all stay `:text`
            # with `:emphasis` as the only active span parser) — kept as a
            # symmetric guard against a future kramdown release adding a span
            # node type this method doesn't already handle, matching the
            # block-level fallback above. Degrades to literal text under
            # whichever bold/italic context was already active at this
            # position, rather than crashing.
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
      # `:escaped_chars` (kramdown's `\X` -> literal `X` rule, covering `*`
      # and `_` among other characters) sits alongside `:emphasis` rather
      # than being left out: without it, `\*escaped*` came back with
      # "escaped" wrongly italicized, because the bare backslash passed
      # through as literal text while the `*...*` on either side of it
      # still paired up as a real emphasis span. Real mmdc (`marked`'s
      # lexer) treats a backslash-escaped marker as literal and inert —
      # verified directly: `\*escaped* text` renders `<p>*escaped*
      # text</p>`, no `<em>`.
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
      # Codex round 6 High: `parse_lines`/`literal_lines` used to produce an
      # empty runs array for a blank-line paragraph gap, and this method
      # carried that gap's height forward onto the next line's `dy` (two
      # blank lines shifted the following line by three line-heights, not
      # one) — but real mmdc's zero-margin paragraph CSS collapses any
      # number of blank lines between two paragraphs to a single normal
      # line-height advance, same as a plain hard break. Neither producer
      # emits an empty runs array anymore (see `literal_lines` and the
      # `:blank` case in `parse_lines`), so `pending_lines` in practice is
      # now always exactly 1 for every non-first line — the accumulation
      # loop below is kept general (it still does the right thing if a
      # future caller ever does pass an empty runs array) rather than
      # special-cased down to a per-line constant.
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
