# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::MarkdownText do
  describe '.parse_lines' do
    # Mutation-check: remove the `raw.scrub unless raw.valid_encoding?` guard.
    # Watched red: raises ArgumentError instead of degrading to a run.
    it 'degrades invalid UTF-8 byte sequences to a scrubbed literal run instead of raising' do
      bad = "hello#{(+"\xFF\xFE").force_encoding('UTF-8')}"

      expect { described_class.parse_lines(bad) }.not_to raise_error
      expect(described_class.parse_lines(bad)).to eq([[described_class::Run.new(text: bad.scrub, bold: false, italic: false)]])
    end

    # Mutation-check: remove `transcode_binary_to_utf8`'s call (or its
    # `raw.encoding == Encoding::ASCII_8BIT` guard). Watched red: raises
    # Encoding::UndefinedConversionError from inside kramdown's own
    # String#encode, because ASCII-8BIT always reports `valid_encoding? ==
    # true`, so the `raw.scrub unless raw.valid_encoding?` guard above never
    # fires for it.
    it 'degrades an ASCII-8BIT-tagged string with a non-ASCII byte instead of raising' do
      bad = (+"hello *world* caf\xE9").force_encoding('ASCII-8BIT')
      expected_tail = (+"\xE9").force_encoding('ASCII-8BIT').encode(Encoding::UTF_8, invalid: :replace, undef: :replace)

      expect { described_class.parse_lines(bad) }.not_to raise_error
      expect(described_class.parse_lines(bad)).to eq([[
                                                       described_class::Run.new(text: 'hello ', bold: false, italic: false),
                                                       described_class::Run.new(text: 'world', bold: false, italic: true),
                                                       described_class::Run.new(text: " caf#{expected_tail}", bold: false, italic: false)
                                                     ]])
    end

    # Mutation-check: change `flatten_runs`'s `:strong` branch to pass
    # `bold` through unchanged instead of forcing it `true` (`flatten_runs(
    # child, bold: bold, italic: italic)`). Watched red: the run comes back
    # plain (`bold: false`) instead of bold.
    it 'renders **bold** as one bold run' do
      lines = described_class.parse_lines('**bold**')

      expect(lines).to eq([[described_class::Run.new(text: 'bold', bold: true, italic: false)]])
    end

    # Mutation-check: the `:em` branch's mirror of the bold mutation above
    # — pass `italic` through unchanged instead of forcing it `true`.
    # Watched red: the run comes back plain instead of italic.
    it 'renders *italic* as one italic run' do
      lines = described_class.parse_lines('*italic*')

      expect(lines).to eq([[described_class::Run.new(text: 'italic', bold: false, italic: true)]])
    end

    # Regression guard for Codex High #2 (kramdown-rewrite round 1): the
    # hand-rolled scanner this module used to have got bold-outer/italic-
    # inner nesting right but italic-outer/bold-inner wrong, and
    # `***both***` (triple marker) wrong in both directions — confirmed
    # against real mmdc output. `flatten_runs`'s recursive descent tracks
    # both flags independently down the real kramdown tree, so nesting
    # order no longer matters.
    it 'nests bold and italic, merging flags rather than overriding them' do
      lines = described_class.parse_lines('**bold *and italic* end**')

      expect(lines).to eq([[
                            described_class::Run.new(text: 'bold ', bold: true, italic: false),
                            described_class::Run.new(text: 'and italic', bold: true, italic: true),
                            described_class::Run.new(text: ' end', bold: true, italic: false)
                          ]])
    end

    # Same regression, the other nesting order: italic outer, bold inner.
    # mmdc: `*italic **bold** end*` -> `<em>italic <strong>bold</strong>
    # end</em>`, so "italic " and " end" stay italic-only and "bold" picks
    # up both flags.
    it 'nests italic-outer/bold-inner the other way round, still merging flags' do
      lines = described_class.parse_lines('*italic **bold** end*')

      expect(lines).to eq([[
                            described_class::Run.new(text: 'italic ', bold: false, italic: true),
                            described_class::Run.new(text: 'bold', bold: true, italic: true),
                            described_class::Run.new(text: ' end', bold: false, italic: true)
                          ]])
    end

    # Triple marker: mmdc renders `***both***` as `<em><strong>both</strong
    # ></em>` — one run, both flags true. The hand-rolled scanner picked
    # `**` as the marker at position 0 (longer marker always wins) and
    # then had no `*` left to open an italic span, so it never set
    # `italic` at all.
    it 'renders ***both*** as one run with both bold and italic' do
      lines = described_class.parse_lines('***both***')

      expect(lines).to eq([[described_class::Run.new(text: 'both', bold: true, italic: true)]])
    end

    # Regression guard for Codex High #3 (kramdown-rewrite round 1): a hard
    # line break embedded inside an open bold span used to be invisible to
    # the per-line scanner (it split the raw string on "\n" BEFORE parsing
    # markup, so each half saw an unmatched, unstyled "**"). mmdc:
    # `**a\nb**` -> `<strong>a<br/>b</strong>` — both halves stay bold.
    # `parse_lines` now parses the whole text as one kramdown document
    # first, so the embedded "\n" stays inside the `strong` node's text and
    # `split_on_hard_breaks` carries the run's flags across the split it
    # introduces.
    it 'keeps a bold run styled on both sides of a hard break inside it' do
      lines = described_class.parse_lines("**a\nb**")

      expect(lines).to eq([
                            [described_class::Run.new(text: 'a', bold: true, italic: false)],
                            [described_class::Run.new(text: 'b', bold: true, italic: false)]
                          ])
    end

    # Kramdown's own flanking rule (an `Kramdown::Parser::Kramdown#emphasis`
    # behavior this module no longer implements itself, only configures
    # `Parser` to use) — pinned here as a dependency-contract check rather
    # than a mutation-check: a kramdown upgrade that loosened flanking
    # would still show up as a red example here.
    it 'leaves an unmatched or improperly flanked marker as literal text' do
      expect(described_class.parse_lines('lone * star'))
        .to eq([[described_class::Run.new(text: 'lone * star', bold: false, italic: false)]])

      expect(described_class.parse_lines('lone ** double'))
        .to eq([[described_class::Run.new(text: 'lone ** double', bold: false, italic: false)]])

      expect(described_class.parse_lines('a * b * c'))
        .to eq([[described_class::Run.new(text: 'a * b * c', bold: false, italic: false)]])

      # Space before the closer: mmdc-verified to never close.
      expect(described_class.parse_lines('**bold **still'))
        .to eq([[described_class::Run.new(text: '**bold **still', bold: false, italic: false)]])
    end

    # Negative-space coverage: this spec exists to fail if backtick
    # stripping is ever added without an mmdc citation. mmdc never renders
    # backtick-fenced content specially inside a kanban label — it is
    # literal passthrough, same as any other character.
    it 'treats a backtick as a plain literal character, never a style marker' do
      lines = described_class.parse_lines('`code`')

      expect(lines).to eq([[described_class::Run.new(text: '`code`', bold: false, italic: false)]])
    end

    # A tab or 4+ leading spaces matches neither kramdown's `:paragraph`
    # parser nor `:blank_line`, so its own line-scanning fallback can emit a
    # bare `:text` block at root instead of `:p` — this must never crash.
    # No `*`/`_` here, so it never reaches kramdown at all (the marker-free
    # early exit below takes it straight to `literal_lines`); the examples
    # further down force the marker path to actually exercise the fallback.
    it 'treats a tab-leading line as literal text instead of crashing' do
      lines = described_class.parse_lines("\tIndented Label")

      expect(lines).to eq([[described_class::Run.new(text: "\tIndented Label", bold: false, italic: false)]])
    end

    it 'treats a four-space-leading line as literal text instead of crashing' do
      lines = described_class.parse_lines('    Four spaces label')

      expect(lines).to eq([[described_class::Run.new(text: '    Four spaces label', bold: false, italic: false)]])
    end

    # Same shapes as the two examples above, but with a trailing unflanked
    # `*` so the raw text reaches the real kramdown-based path instead of
    # the marker-free early exit — this is what actually exercises
    # `parse_lines`'s unexpected-block fallback (deleting the
    # `root.children.any? { ... }` guard raises `NoMethodError` walking a
    # bare root-level `:text` block). A trailing UNFLANKED `*` is required:
    # a well-formed pair like `*word*` fragments the tree differently (see
    # the regression guard below), which the same guard also catches.
    it 'treats a tab-leading line with a marker as literal text via the real parse path' do
      lines = described_class.parse_lines("\tIndented Label*")

      expect(lines).to eq([[described_class::Run.new(text: "\tIndented Label*", bold: false, italic: false)]])
    end

    it 'treats a four-space-leading line with a marker as literal text via the real parse path' do
      lines = described_class.parse_lines('    Four spaces label*')

      expect(lines).to eq([[described_class::Run.new(text: '    Four spaces label*', bold: false, italic: false)]])
    end

    # Same fallback shape, but reached from a second line after a hard
    # break: the blank line between "a*" and the tab-led "b" is what breaks
    # kramdown's lazy paragraph continuation (a tab-led SECOND line with no
    # blank stays inside `:p` and never reaches this fallback). Whole-string
    # fallback and per-node reconstruction happen to agree here, so this
    # shape alone can't distinguish the two mechanisms — see the regression
    # guard below for that. The blank-line gap collapses to zero extra rows
    # (matches real mmdc, not a distinct blank line).
    it 'treats a tab-leading line after a blank line as literal text, with the blank gap collapsed' do
      lines = described_class.parse_lines("a*\n\n\tb")

      expect(lines).to eq([
                            [described_class::Run.new(text: 'a*', bold: false, italic: false)],
                            [described_class::Run.new(text: "\tb", bold: false, italic: false)]
                          ])
    end

    # The round-2 fallback above reconstructed literal text per unexpected
    # NODE, not the whole STRING — but kramdown span-parses inside its own
    # block-level fallback, so a marker anywhere can split one source line
    # into several sibling blocks, each then treated as its own literal
    # line. `"\t*hello* world"` is exactly this shape (three siblings, none
    # `:p`); the per-node handling this replaced turned it into three
    # fragmented, unstyled lines with the `*` chars silently gone. Must
    # instead fall back to `literal_lines(raw)` for the whole string.
    it 'falls back to the whole raw string, not a fragmented per-node reconstruction' do
      raw = "\t*hello* world"

      expect(described_class.parse_lines(raw)).to eq(described_class.literal_lines(raw))
    end

    # Guards the OTHER shape of "indented mid-label text": a four-space-led
    # line immediately continuing a paragraph (no blank line between) stays
    # inside kramdown's lazy `:p` continuation and never reaches the
    # fallback block at all — the embedded `\n` still becomes an ordinary
    # hard break. A trailing unflanked `*` on "a" is required, same reason
    # as the tab-led examples above: with no marker at all the text never
    # reaches `Parser.parse` (the marker-free early exit takes it straight
    # to `literal_lines`), so an unmarked version would pass even with
    # `Parser.parse` replaced by an unconditional exception.
    it 'keeps an indented continuation line inside the paragraph, unaffected by the fallback' do
      lines = described_class.parse_lines("a*\n    b")

      expect(lines).to eq([
                            [described_class::Run.new(text: 'a*', bold: false, italic: false)],
                            [described_class::Run.new(text: '    b', bold: false, italic: false)]
                          ])
    end

    # `split_on_hard_breaks` must start a new line per split part, not join
    # them back together. A trailing unflanked `*` on the first line is
    # required: with no marker at all, the marker-free early exit sends the
    # raw text to `literal_lines` instead (which coincidentally produces the
    # same two-line shape without ever calling `split_on_hard_breaks`).
    it 'splits on a literal newline as a hard line break' do
      lines = described_class.parse_lines("Line one*\nLine two")

      expect(lines).to eq([
                            [described_class::Run.new(text: 'Line one*', bold: false, italic: false)],
                            [described_class::Run.new(text: 'Line two', bold: false, italic: false)]
                          ])
    end

    # Two separate marked spans, not nested inside each other. This
    # distinguishes "each open closes at its own nearest valid closer"
    # from a bug that would instead close the first `**` at the LAST `**`
    # in the line, swallowing "plain" into one giant bold run.
    it 'keeps two separate bold spans on one line distinct, not merged' do
      lines = described_class.parse_lines('**a** plain **b**')

      expect(lines).to eq([[
                            described_class::Run.new(text: 'a', bold: true, italic: false),
                            described_class::Run.new(text: ' plain ', bold: false, italic: false),
                            described_class::Run.new(text: 'b', bold: true, italic: false)
                          ]])
    end

    # A backslash-escaped marker must stay literal, not open styling: real
    # mmdc treats `\*` as an escape, consuming the backslash so the `*`
    # that follows can't pair with a later `*`. Requires `:escaped_chars`
    # in `Parser`'s `@span_parsers` — without it the backslash itself comes
    # back literal and the following `*...*` still opens italics.
    it 'treats a backslash-escaped marker as literal, never a style trigger' do
      lines = described_class.parse_lines('\*escaped* text')

      expect(lines).to eq([[described_class::Run.new(text: '*escaped* text', bold: false, italic: false)]])
    end

    # Same fix, but escaped markers sitting next to REAL emphasis on the
    # same line — distinguishes "escapes are recognized" from "escapes
    # happen to disable all emphasis parsing on the line". mmdc:
    # `task1[**a** \*b\* **c**]` -> `<strong>a</strong> *b* <strong>c</strong>`.
    it 'keeps an escaped marker literal alongside real emphasis on the same line' do
      lines = described_class.parse_lines('**a** \*b\* **c**')

      expect(lines).to eq([[
                            described_class::Run.new(text: 'a', bold: true, italic: false),
                            described_class::Run.new(text: ' *b* ', bold: false, italic: false),
                            described_class::Run.new(text: 'c', bold: true, italic: false)
                          ]])
    end

    # A kramdown-specific DoS: kramdown's `:emphasis` parser backtracks on
    # ambiguous markers at worse-than-quadratic cost, so a label carrying
    # more markers than `MAX_EMPHASIS_MARKERS` must never reach kramdown at
    # all. Uses well-formed `**x** ` pairs, not ambiguous single markers:
    # kramdown never resolves `"*a " * 100` into any styled node even under
    # the cap, so that shape can't tell "fallback skipped kramdown" apart
    # from "kramdown ran and found nothing to style" — only `"**x** "`,
    # which DOES parse into styled nodes under the cap, isolates the guard.
    it 'falls back to unstyled literal text past MAX_EMPHASIS_MARKERS, never parsing markup' do
      long_text = "**x** " * 10

      expect(long_text.count('*_')).to be > described_class::MAX_EMPHASIS_MARKERS

      lines = described_class.parse_lines(long_text)

      expect(lines).to eq([[described_class::Run.new(text: long_text, bold: false, italic: false)]])
    end

    # The marker-count fallback still respects hard line breaks — it skips
    # kramdown, not line-splitting. Built from well-formed `**x** ` pairs,
    # not ambiguous single markers, for the same isolation reason as the
    # guard above (an unmatched `*` comes back literal regardless of
    # whether the guard fires). Asserts the whole result, not just
    # `lines.last`: a mutation dropping every line but the last would still
    # satisfy an assertion on `lines.last` alone.
    it 'still splits on hard line breaks in the marker-count unstyled fallback' do
      first_line = '**x** ' * 8
      long_text = "#{first_line}\nsecond"

      expect(long_text.count('*_')).to be > described_class::MAX_EMPHASIS_MARKERS
      expect(long_text.length).to be <= described_class::MAX_PARSEABLE_LENGTH

      lines = described_class.parse_lines(long_text)

      expect(lines).to eq([
                            [described_class::Run.new(text: first_line, bold: false, italic: false)],
                            [described_class::Run.new(text: 'second', bold: false, italic: false)]
                          ])
    end

    # An escaped marker must not count toward `MAX_EMPHASIS_MARKERS`:
    # `:escaped_chars` consumes it as one cheap, fixed-cost substitution
    # before `:emphasis` ever sees it, so it can never reach the
    # backtracking this guard bounds. Before this fix, enough escaped
    # markers wrongly tripped the guard and fell back to `literal_lines`,
    # which keeps every backslash in the output — visibly wrong, not just
    # unstyled.
    it 'does not count escaped markers toward MAX_EMPHASIS_MARKERS' do
      raw = '\*' * (described_class::MAX_EMPHASIS_MARKERS + 1)

      lines = described_class.parse_lines(raw)

      expect(lines).to eq([[
                            described_class::Run.new(
                              text: '*' * (described_class::MAX_EMPHASIS_MARKERS + 1), bold: false, italic: false
                            )
                          ]])
    end

    # The LENGTH backstop still respects hard line breaks too, independent
    # of the marker-count guard above — built from a single leading `*`
    # (one marker total, nowhere near `MAX_EMPHASIS_MARKERS`) followed by
    # filler past `MAX_PARSEABLE_LENGTH`, so only the length backstop
    # explains the fallback here.
    it 'still splits on hard line breaks in the length-backstop unstyled fallback' do
      padding = "a" * (described_class::MAX_PARSEABLE_LENGTH - "**x**".length + 1)
      first_line = "**x**#{padding}"
      long_text = "#{first_line}\nsecond"

      expect(first_line.count('*_')).to be <= described_class::MAX_EMPHASIS_MARKERS
      expect(long_text.length).to be > described_class::MAX_PARSEABLE_LENGTH

      lines = described_class.parse_lines(long_text)

      expect(lines).to eq([
                            [described_class::Run.new(text: first_line, bold: false, italic: false)],
                            [described_class::Run.new(text: 'second', bold: false, italic: false)]
                          ])
    end

    # The length backstop is independent of the marker-count guard and
    # must be reachable on its own: a huge label with only ONE marker pair
    # (nowhere near `MAX_EMPHASIS_MARKERS`) still has to fall back once it
    # crosses `MAX_PARSEABLE_LENGTH`, or the backstop constant is dead code
    # no spec would ever catch. Mutation-check: delete the length guard in
    # `parse_lines`. Watched red: this example's marker count stays low
    # (proving the marker-count guard alone would NOT have triggered a
    # fallback) but the run still comes back as one literal run rather than
    # a styled bold run once the length guard is live.
    it 'falls back on length alone when marker count is low but the label is huge' do
      padding = "a" * (described_class::MAX_PARSEABLE_LENGTH - "**x**".length + 1)
      long_text = "**x**#{padding}"

      expect(long_text.count('*_')).to be <= described_class::MAX_EMPHASIS_MARKERS
      expect(long_text.length).to be > described_class::MAX_PARSEABLE_LENGTH

      lines = described_class.parse_lines(long_text)

      expect(lines).to eq([[described_class::Run.new(text: long_text, bold: false, italic: false)]])
    end

    # The actual behavior this round's High fixes: an ordinary label with
    # normal prose length but only a couple of markers must render STYLED,
    # not fall back — this is the exact case Codex cited (a 51-character
    # label with one bold word losing its styling under the old
    # length-only cap). Verified directly against real mmdc: `<strong>` is
    # rendered around "proposed".
    it 'styles an ordinary long label with few markers instead of falling back' do
      long_text = 'Please review the **proposed** deployment plan asap and get back to ' \
                  'the team before the end of the day tomorrow'

      expect(long_text.length).to be > 50
      expect(long_text.count('*_')).to be <= described_class::MAX_EMPHASIS_MARKERS

      lines = described_class.parse_lines(long_text)

      expect(lines).to eq([[
                            described_class::Run.new(text: 'Please review the ', bold: false, italic: false),
                            described_class::Run.new(text: 'proposed', bold: true, italic: false),
                            described_class::Run.new(
                              text: ' deployment plan asap and get back to the team before the end of ' \
                                    'the day tomorrow', bold: false, italic: false
                            )
                          ]])
    end

    # Amplification High: text with no `*` character at all can still be
    # styled, because kramdown's `:emphasis` parser also fires on `_`
    # (`EMPHASIS_START = /(?:\*\*?|__?)/`). Mutation-check: narrow
    # `EMPHASIS_MARKER` to `/\*/`. Watched red: this comes back as one
    # literal run instead of one italic one, since the narrowed predicate
    # would send underscore-only text straight to `literal_lines` without
    # ever calling kramdown.
    it 'still parses underscore-only italic markup through the marker-free early exit guard' do
      lines = described_class.parse_lines('_italic_')

      expect(lines).to eq([[described_class::Run.new(text: 'italic', bold: false, italic: true)]])
    end

    # Boundary: exactly MAX_EMPHASIS_MARKERS markers still gets parsed
    # normally (the guard is `> MAX_EMPHASIS_MARKERS`, not `>=`). Verified
    # directly against `Parser` before writing this: 15 well-formed `*a* `
    # spans (2 markers each = 30 total) come back as 15 italic "a" runs
    # with 14 plain-space runs between them — kramdown trims the
    # paragraph's OWN trailing whitespace, so there's no 15th trailing
    # space run.
    it 'parses markup normally at exactly MAX_EMPHASIS_MARKERS markers' do
      segment_count = described_class::MAX_EMPHASIS_MARKERS / 2
      text = '*a* ' * segment_count
      expect(text.count('*_')).to eq(described_class::MAX_EMPHASIS_MARKERS)

      lines = described_class.parse_lines(text)

      expected_runs = [described_class::Run.new(text: 'a', bold: false, italic: true)]
      (segment_count - 1).times do
        expected_runs << described_class::Run.new(text: ' ', bold: false, italic: false)
        expected_runs << described_class::Run.new(text: 'a', bold: false, italic: true)
      end

      expect(lines).to eq([expected_runs])
    end

    # One marker past the boundary falls back to fully literal text, even
    # though the trailing lone `*` here isn't well-formed markup anyway —
    # the guard fires on raw count before kramdown ever runs, so the text
    # doesn't need to be valid markup to prove the guard is live.
    it 'falls back once marker count exceeds MAX_EMPHASIS_MARKERS by one' do
      segment_count = described_class::MAX_EMPHASIS_MARKERS / 2
      text = "#{'*a* ' * segment_count}*"
      expect(text.count('*_')).to eq(described_class::MAX_EMPHASIS_MARKERS + 1)

      lines = described_class.parse_lines(text)

      expect(lines).to eq([[described_class::Run.new(text: text, bold: false, italic: false)]])
    end

    # Boundary for `MAX_PARSEABLE_LENGTH` itself — the marker-count
    # boundary pair above never exercises this guard; both stay far under
    # it. Uses a well-formed `'**x**'` pair as filler, not a bare unmatched
    # marker: an unmatched marker comes back literal from kramdown's own
    # flanking rules regardless of whether this guard fires, so it can't
    # distinguish "the guard is live" from "kramdown found nothing to
    # style".
    it 'parses markup normally at exactly MAX_PARSEABLE_LENGTH characters' do
      padding = 'a' * (described_class::MAX_PARSEABLE_LENGTH - '**x**'.length)
      text = "**x**#{padding}"
      expect(text.length).to eq(described_class::MAX_PARSEABLE_LENGTH)

      lines = described_class.parse_lines(text)

      expect(lines).to eq([[
                            described_class::Run.new(text: 'x', bold: true, italic: false),
                            described_class::Run.new(text: padding, bold: false, italic: false)
                          ]])
    end

    it 'falls back once length exceeds MAX_PARSEABLE_LENGTH by one' do
      padding = 'a' * (described_class::MAX_PARSEABLE_LENGTH - '**x**'.length + 1)
      text = "**x**#{padding}"
      expect(text.length).to eq(described_class::MAX_PARSEABLE_LENGTH + 1)

      lines = described_class.parse_lines(text)

      expect(lines).to eq([[described_class::Run.new(text: text, bold: false, italic: false)]])
    end

    # Underscore escape coverage: the two escape specs above only ever use
    # `\*`, even though `EMPHASIS_MARKER = /[*_]/` and `:escaped_chars`
    # claims to cover both markers — this is pure spec-coverage, no
    # production change. Requires `:escaped_chars` in `Parser`'s
    # `@span_parsers` (same guard the `\*` version above checks).
    it 'treats a backslash-escaped underscore as literal, never a style trigger' do
      lines = described_class.parse_lines('\_escaped_ text')

      expect(lines).to eq([[described_class::Run.new(text: '_escaped_ text', bold: false, italic: false)]])
    end

    # An escaped marker that leaves exactly one unescaped marker of the
    # same character immediately behind it, which then meets a
    # differently-sized run later, diverges from real mmdc (see
    # `unsafe_escaped_delimiter_interaction?`'s comment for the full
    # measurement) — running it straight through kramdown gets a different
    # wrong answer per shape. Falls back to `literal_lines` instead: it
    # doesn't reproduce mmdc's fragmented spans, but it is SAFE (no crash,
    # no wrong styling), the same trade-off `MAX_EMPHASIS_MARKERS` accepts.
    it 'falls back to literal text when an escaped marker leaves a lone orphan before a mismatched closer' do
      raw = '**a \** b**'

      expect(described_class.parse_lines(raw)).to eq(described_class.literal_lines(raw))
    end

    it 'falls back to literal text for the escape-first form of the same interaction' do
      raw = '\**a**'

      expect(described_class.parse_lines(raw)).to eq(described_class.literal_lines(raw))
    end

    # The same interaction with `_` instead of `*`, proving the guard isn't
    # marker-specific. mmdc: `task1[__a \__ b__]` renders
    # `<em><em>a _</em> b</em>_`; this module falls back to literal instead.
    it 'falls back to literal text for the same interaction with underscore markers' do
      raw = '__a \__ b__'

      expect(described_class.parse_lines(raw)).to eq(described_class.literal_lines(raw))
    end

    # A SECOND escaped marker sitting between the orphan and the real
    # closing run must not be matched as `next_run` itself — an escaped
    # marker is always exactly one character, so it always looks "safe"
    # and can mask a mismatched closer further on. This example alone
    # doesn't pin the `gsub` specifically: a guard broadened to fire on
    # ANY `next_run` (dropping the length-mismatch check) also passes it —
    # the sibling example below ("does not fall back when a lone orphan
    # cleanly pairs with a same-length closer") catches that broader case;
    # the two together pin the real property.
    it 'falls back to literal text when a second escaped marker sits between the orphan and the real closer' do
      raw = '\**a \* b**'

      expect(described_class.parse_lines(raw)).to eq(described_class.literal_lines(raw))
    end

    # A lone orphan is not unsafe by itself — only a length MISMATCH with
    # the run that eventually closes it is. Verified directly against real
    # mmdc before writing this: `task1[a\**b*]` renders `a*<em>b</em>`,
    # matching this module unchanged (a clean single-to-single pairing).
    # Guards against a guard that's too broad: mutation-check by loosening
    # the guard to fire on ANY lone orphan regardless of what follows it
    # (drop the `next_run.length != 1` condition). Watched red: this comes
    # back as `literal_lines(raw)` instead of the styled runs below.
    it 'does not fall back when a lone orphan cleanly pairs with a same-length closer' do
      lines = described_class.parse_lines('a\**b*')

      expect(lines).to eq([[
                            described_class::Run.new(text: 'a*', bold: false, italic: false),
                            described_class::Run.new(text: 'b', bold: false, italic: true)
                          ]])
    end

    # A run of two or more unescaped markers right after the escape pairs
    # cleanly with itself and is never treated as a lone orphan. Verified
    # directly against real mmdc: `task1[**\*x\***]` renders
    # `<strong>*x*</strong>`, matching this module unchanged.
    it 'does not fall back when the escape is followed by a two-or-more marker run' do
      lines = described_class.parse_lines('**\*x\***')

      expect(lines).to eq([[described_class::Run.new(text: '*x*', bold: true, italic: false)]])
    end

    # The OTHER half of the blank-line fix (`literal_lines` covers the
    # marker-free fallback path; this covers the real kramdown `Parser`
    # path, reached only when `raw` contains a `*`/`_` — a genuinely
    # different code path, the `:blank` case in `parse_lines` itself). A
    # blank-line paragraph gap between two `:p` blocks must contribute no
    # extra line, matching real mmdc's zero-margin paragraph CSS.
    it 'collapses a blank-line paragraph gap to no extra lines on the real kramdown parse path' do
      lines = described_class.parse_lines("**A**\n\nB")

      expect(lines).to eq([
                            [described_class::Run.new(text: 'A', bold: true, italic: false)],
                            [described_class::Run.new(text: 'B', bold: false, italic: false)]
                          ])
    end

    # kramdown's emphasis grammar disagrees with real `marked` on these
    # four short, valid labels — not just unstyled but WRONG (markers leak
    # into visible text, or inner markers vanish). Correct (marked) output:
    # `****foo****` -> bold "foo" (Guard A); `**foo* bar**` -> italic
    # "foo bar", trailing literal `*` (Guard B); `_*a*_` -> italic "a"
    # (Guard C); `**foo **bar****` -> bold "foo bar". Each falls back to
    # `literal_lines` rather than risk a wrong render. Not a pin on
    # `unsafe_delimiter_run_structure?` by name:
    # `unsafe_emphasis_divergence?` independently re-derives "unsafe" for
    # the same four shapes, so these examples pin the end-to-end safety
    # property, not one fast-path guard.
    it 'falls back to literal text for a 4-or-more marker run (Guard A)' do
      raw = '****foo****'

      expect(described_class.parse_lines(raw)).to eq(described_class.literal_lines(raw))
    end

    it 'falls back to literal text for a run-length sequence that leaves an interior run dangling (Guard B)' do
      raw = '**foo* bar**'

      expect(described_class.parse_lines(raw)).to eq(described_class.literal_lines(raw))
    end

    it 'falls back to literal text for a single-marker nested wrap across the two delimiter characters (Guard C)' do
      raw = '_*a*_'

      expect(described_class.parse_lines(raw)).to eq(described_class.literal_lines(raw))
    end

    it 'falls back to literal text when a trailing 4-run closes two nested bold spans' do
      raw = '**foo **bar****'

      expect(described_class.parse_lines(raw)).to eq(described_class.literal_lines(raw))
    end

    # Guard C is deliberately narrower than "any `*`/`_` adjacency": a
    # SEQUENTIAL pair — one span's close immediately followed by the next
    # span's open — is a different, already-safe shape and must not route
    # to `literal_lines` (`*a*_b_` -> independent italics, no
    # cross-interaction). An earlier, cruder adjacency-only version of
    # Guard C false-positived on exactly this shape.
    it 'keeps a sequential (non-nested) run of two single markers of different characters styled' do
      lines = described_class.parse_lines('*a*_b_')

      expect(lines).to eq([[
                            described_class::Run.new(text: 'a', bold: false, italic: true),
                            described_class::Run.new(text: 'b', bold: false, italic: true)
                          ]])
    end

    it 'keeps the reverse-order sequential single-marker run styled too' do
      lines = described_class.parse_lines('_a_*b*')

      expect(lines).to eq([[
                            described_class::Run.new(text: 'a', bold: false, italic: true),
                            described_class::Run.new(text: 'b', bold: false, italic: true)
                          ]])
    end

    # `**a*a**` and the genuinely-unsafe `"**foo* bar**"` above share the
    # same `*`-run shape `[2,1,2]`; only flanking context tells them apart.
    #
    # Mutation-check: temporarily restore the old Guard B call in place of
    # `unsafe_emphasis_divergence?`. Watched red: this falls back to
    # `literal_lines`, `**a*a**`, instead of one bold run.
    it 'keeps a run-length sequence styled when it matches marked exactly, unlike the superficially identical Guard B case' do
      lines = described_class.parse_lines('**a*a**')

      expect(lines).to eq([[described_class::Run.new(text: 'a*a', bold: true, italic: false)]])
    end

    # A second, genuine kramdown/marked divergence `unsafe_emphasis_divergence?`
    # catches where the old Guard B never modeled cross-type nesting at
    # all: kramdown parses this as one italic run with the inner `*b*`
    # left as literal markers inside it (verified directly:
    # `<em>a *b* c</em>`), while real `marked.parseInline` parses the
    # inner span too (`<em>a <em>b</em> c</em>`, nested italic-in-italic).
    # Neither shape is reproducible without genuinely re-parsing, so this
    # falls back to `literal_lines` rather than risk either wrong render —
    # same trade-off as every other guard in this file.
    it 'falls back to literal text for a cross-type nesting shape marked and kramdown resolve differently' do
      raw = '_a *b* c_'

      expect(described_class.parse_lines(raw)).to eq(described_class.literal_lines(raw))
    end
  end
end
