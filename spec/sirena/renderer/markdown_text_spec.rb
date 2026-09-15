# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::Renderer::MarkdownText do
  describe '.parse_lines' do
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

    # Blocker regression guard: a tab or 4+ leading spaces matches neither
    # kramdown's `:paragraph` parser (excludes lines starting with tab/OPT_SPACE
    # overflow) nor `:blank_line`, and `:codeblock` isn't registered, so
    # kramdown's own line-scanning fallback (`Parser::Kramdown#parse_blocks`'s
    # `add_text(@src.scan(/.*\n/))` branch) appends a bare `:text` block
    # directly under root instead of wrapping it in `:p`. Reproduced with the
    # real CLI before this fix: `kanban\n  col[Column]\n    c1[<TAB>Indented
    # Label]` crashed `bundle exec exe/sirena render` with "unexpected
    # kramdown block :text in a markdown label". Ordinary diagram source, not
    # a crafted edge case.
    #
    # No `*`/`_` in this text, so it never reaches kramdown at all —
    # `parse_lines`'s marker-free early exit (below) takes it straight to
    # `literal_lines`. Kept because it's the foreman's exact repro shape and
    # it must still never crash; the examples further down force text
    # through the real kramdown-based path to actually exercise the
    # unexpected-block fallback this comment describes.
    it 'treats a tab-leading line as literal text instead of crashing' do
      lines = described_class.parse_lines("\tIndented Label")

      expect(lines).to eq([[described_class::Run.new(text: "\tIndented Label", bold: false, italic: false)]])
    end

    it 'treats a four-space-leading line as literal text instead of crashing' do
      lines = described_class.parse_lines('    Four spaces label')

      expect(lines).to eq([[described_class::Run.new(text: '    Four spaces label', bold: false, italic: false)]])
    end

    # Same shapes as the two examples above, but with a trailing unflanked
    # `*` so the raw text contains a marker character and reaches the real
    # kramdown-based path instead of the marker-free early exit — this is
    # what actually exercises `parse_lines`'s unexpected-block fallback.
    # Mutation-check: delete the `return literal_lines(raw) if
    # root.children.any? { ... }` guard. Watched red: both examples raise
    # `NoMethodError` walking a bare root-level `:text` block that isn't `:p`
    # or `:blank`. A trailing UNFLANKED `*` (no closing partner) is required,
    # not any marker: a well-formed pair like `*word*` still fragments the
    # tree into several sibling blocks (see the regression guard below for
    # exactly that shape), which is also caught by the same guard — either
    # marker shape demonstrates it, this one happens to be the simplest.
    it 'treats a tab-leading line with a marker as literal text via the real parse path' do
      lines = described_class.parse_lines("\tIndented Label*")

      expect(lines).to eq([[described_class::Run.new(text: "\tIndented Label*", bold: false, italic: false)]])
    end

    it 'treats a four-space-leading line with a marker as literal text via the real parse path' do
      lines = described_class.parse_lines('    Four spaces label*')

      expect(lines).to eq([[described_class::Run.new(text: '    Four spaces label*', bold: false, italic: false)]])
    end

    # Same fallback shape, reached from a second line after a hard break
    # rather than the first line of the text — the blank line between "a"
    # and the tab-led "b" is what breaks kramdown's lazy paragraph
    # continuation (verified: a tab-led SECOND line with no intervening
    # blank stays inside the `:p` and never reaches this fallback at all).
    # The marker on "a*" keeps the whole raw string off the early-exit path
    # (see the two examples above).
    #
    # Whole-string fallback and per-node reconstruction happen to agree here
    # — "a*" never shares a block with the tab-led "b", so nothing is lost
    # either way — which is exactly why this shape alone can't stand in for
    # the regression guard below: it can't tell the two mechanisms apart.
    #
    # Codex round 6 High: the blank line between "a*" and "\tb" no longer
    # produces its own `[]` line in the output — see `literal_lines`'
    # comment for why (real mmdc collapses any blank-line gap to zero extra
    # vertical space, matching a plain hard break, not a distinct row).
    it 'treats a tab-leading line after a blank line as literal text, with the blank gap collapsed' do
      lines = described_class.parse_lines("a*\n\n\tb")

      expect(lines).to eq([
                            [described_class::Run.new(text: 'a*', bold: false, italic: false)],
                            [described_class::Run.new(text: "\tb", bold: false, italic: false)]
                          ])
    end

    # Round-3 Codex High: the round-2 fallback above reconstructed literal
    # text per unexpected NODE rather than falling back for the whole
    # STRING, and kramdown span-parses inside its own block-level fallback —
    # so a marker anywhere in the text can split a single source line into
    # several independent sibling blocks, each then treated as its own
    # literal line. `"\t*hello* world"` is exactly this: kramdown emits a
    # root-level `:text` ("\t"), `:em` ("hello"), `:text` (" world") — three
    # siblings, none of them `:p` — and the per-node handling this replaced
    # turned that into three fragmented, unstyled lines with the `*`
    # characters silently gone. Real mermaid renders this input literally,
    # unchanged, as ONE line — exactly what `literal_lines` already gives
    # every other unparseable label.
    #
    # Mutation-check: replace the `root.children.any? { ... }` guard's whole
    # `literal_lines(raw)` fallback with the old per-node reconstruction.
    # Watched red: `parse_lines` returns three lines
    # (`["\t", "hello", " world"]`) instead of matching `literal_lines`.
    it 'falls back to the whole raw string, not a fragmented per-node reconstruction' do
      raw = "\t*hello* world"

      expect(described_class.parse_lines(raw)).to eq(described_class.literal_lines(raw))
    end

    # Guards the OTHER shape of "indented mid-label text": a four-space-led
    # line immediately continuing a paragraph (no blank line between) stays
    # inside kramdown's lazy `:p` continuation and never reaches the
    # fallback block at all — the embedded `\n` still becomes an ordinary
    # hard break, splitting into two lines exactly as it did before this
    # fix (the leading spaces on "b" are literal content, not consumed as
    # indentation, since no `:codeblock` parser is active to interpret them).
    #
    # A trailing unflanked `*` on "a" is required, same reason as the tab-led
    # examples above: with no marker at all the raw text never reaches
    # `Parser.parse` (`parse_lines`'s marker-free early exit takes it
    # straight to `literal_lines`), so an unmarked version of this example
    # would pass even with `Parser.parse` replaced by an unconditional
    # exception — it would never call it.
    it 'keeps an indented continuation line inside the paragraph, unaffected by the fallback' do
      lines = described_class.parse_lines("a*\n    b")

      expect(lines).to eq([
                            [described_class::Run.new(text: 'a*', bold: false, italic: false)],
                            [described_class::Run.new(text: '    b', bold: false, italic: false)]
                          ])
    end

    # Mutation-check: in `split_on_hard_breaks`, join `run.text.split("\n",
    # -1)`'s parts back together instead of starting a new line per part
    # (drop the `lines << [] if index.positive?`). Watched red: one
    # line/run with both sentences run together instead of two line-groups.
    #
    # A trailing unflanked `*` on the first line is required: with no marker
    # at all, `parse_lines`'s marker-free early exit sends the raw text
    # straight to `literal_lines` (which also splits on "\n", coincidentally
    # producing the same two-line shape) without ever calling
    # `split_on_hard_breaks` — so an unmarked version of this example would
    # pass even with `split_on_hard_breaks` itself replaced by an
    # unconditional exception.
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

    # Codex round 3 High: a backslash-escaped marker was rendered as
    # styling instead of staying literal. Real mmdc (`marked`'s lexer)
    # treats `\*` as an escape — the backslash is consumed and the `*`
    # that follows is plain text, so it can't pair with a later `*` to
    # open italics. Verified directly against real mmdc:
    # `task1[\*escaped* text]` renders `<p>*escaped* text</p>`, no `<em>`.
    # `Parser` restricted kramdown to only `:emphasis` before this fix, so
    # the backslash itself came back as literal text and the following
    # `*...*` still paired up and opened italics.
    #
    # Mutation-check: drop `:escaped_chars` from `Parser`'s `@span_parsers`.
    # Watched red: "escaped" comes back as its own italic run instead of
    # the whole string staying one literal run.
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

    # Regression guard for a kramdown-specific DoS found while building
    # this rewrite: kramdown's `:emphasis` parser backtracks on ambiguous
    # markers at worse-than-quadratic cost (measured directly against
    # kramdown, bypassing this module: `"**_a " * n`, the worst pattern
    # found, costs ~1.2s aggregate across 300 cards at exactly
    # `MAX_EMPHASIS_MARKERS` each). No real card or column label needs more
    # than a handful of markers, so a label carrying more markers than
    # `MAX_EMPHASIS_MARKERS` never reaches kramdown at all — mutation-check:
    # delete the marker-count guard in `parse_lines`. Watched red: this
    # example still passes its marker-count assertion but the run comes
    # back split into several styled bold runs instead of one literal one.
    #
    # Uses well-formed `**x** ` pairs, not ambiguous single markers: kramdown
    # never resolves `"*a " * 100` into any `:strong`/`:em` node even well
    # under the marker-count cap (proven directly against `Parser` above),
    # so that shape can't tell "the fallback skipped kramdown" apart from
    # "kramdown ran and found nothing to style" — deleting the guard would
    # leave this example green for the wrong reason. `"**x** "` DOES parse
    # into `:strong` nodes under the cap, so only the guard being live
    # explains a single unstyled run here.
    it 'falls back to unstyled literal text past MAX_EMPHASIS_MARKERS, never parsing markup' do
      long_text = "**x** " * 10

      expect(long_text.count('*_')).to be > described_class::MAX_EMPHASIS_MARKERS

      lines = described_class.parse_lines(long_text)

      expect(lines).to eq([[described_class::Run.new(text: long_text, bold: false, italic: false)]])
    end

    # The marker-count fallback still respects hard line breaks — it skips
    # kramdown, not line-splitting. Built from well-formed `**x** ` pairs
    # (as in the primary marker-count regression guard above), not
    # ambiguous single markers: an unmatched `*` would come back literal
    # from kramdown's own flanking rules regardless of whether the guard
    # fires, so that shape can't distinguish "the guard is live" from "the
    # guard is dead but kramdown found nothing to style" — this mutation
    # would NOT have been caught by a single-marker version of this
    # example. Killed (red) with the marker-count guard commented out:
    # comes back as a styled bold run instead of one literal line.
    #
    # Asserts the whole result, not just `lines.last`: a mutation returning
    # `literal_lines(raw).last(1)` (dropping every line but the last) still
    # satisfies an assertion on `lines.last` alone, since `.last` of a
    # one-element array is that element either way.
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

    # Codex round 4 High: an escaped marker used to count toward
    # `MAX_EMPHASIS_MARKERS` the same as a real one, even though
    # `:escaped_chars` consumes it as one cheap, fixed-cost substitution
    # before `:emphasis` ever sees it — it can never reach the backtracking
    # this guard exists to bound. Verified directly against real mmdc:
    # `task1[\*\*\*...(31 times)]` renders 31 bare stars, no backslashes,
    # cheaply. Before this fix, 31 escaped markers wrongly tripped the
    # guard and fell back to `literal_lines`, which keeps every backslash
    # in the output — visibly wrong output, not just lost styling.
    #
    # Mutation-check: revert `real_marker_count` to `raw.count('*_')`.
    # Watched red: the backslashes stay in the output instead of kramdown's
    # `:escaped_chars` stripping them down to bare stars.
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

    # Boundary for `MAX_PARSEABLE_LENGTH` itself: the marker-count boundary
    # pair above never exercises this guard at all — both its examples stay
    # far under
    # `MAX_PARSEABLE_LENGTH`. Uses a well-formed `'**x**'` pair as filler
    # (matching `'falls back on length alone...'` above), not a bare
    # unmatched marker — an unmatched marker comes back literal from
    # kramdown's own flanking rules regardless of whether this guard fires,
    # so it can't distinguish "the guard is live" from "kramdown found
    # nothing to style" (the same trap already caught once this session for
    # a different spec in this file). Mutation-check: change `>` to `>=` on
    # the `MAX_PARSEABLE_LENGTH` guard in `parse_lines`. Watched red: the
    # at-the-cap example below falls back to literal instead of styling.
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

    # Underscore escape coverage: the two escape specs above ('treats a
    # backslash-escaped marker as
    # literal...' and 'keeps an escaped marker literal alongside real
    # emphasis...') only ever use `\*`, even though `EMPHASIS_MARKER =
    # /[*_]/` and this module's own comments claim `:escaped_chars` covers
    # both markers. Verified directly against the real (unmutated) code
    # before writing this — already correct, this is pure spec-coverage,
    # no production change — and against real mmdc:
    # `task1[\_escaped_ text]` renders `<p>_escaped_ text</p>`, no `<em>`.
    #
    # Mutation-check: drop `:escaped_chars` from `Parser`'s `@span_parsers`
    # (same mutation the `\*` version above is checked against). Watched
    # red: "escaped" comes back as its own italic run instead of the whole
    # string staying one literal run.
    it 'treats a backslash-escaped underscore as literal, never a style trigger' do
      lines = described_class.parse_lines('\_escaped_ text')

      expect(lines).to eq([[described_class::Run.new(text: '_escaped_ text', bold: false, italic: false)]])
    end

    # Codex round 4 High: an escaped marker that leaves exactly one
    # unescaped marker of the same character immediately behind it, which
    # then meets a differently-sized run later, diverges from real mmdc
    # (see `unsafe_escaped_delimiter_interaction?`'s comment for the full
    # measurement). Before this fix, `parse_lines` ran these straight
    # through kramdown's `:emphasis`/`:escaped_chars` combination and got a
    # DIFFERENT wrong answer for each: the `**`-opened case merged into one
    # bold run instead of fragmenting, and the escape-first case lost
    # emphasis entirely instead of fragmenting. Falling back to
    # `literal_lines` doesn't reproduce mmdc's fragmented spans either (that
    # would need mmdc's own flanking algorithm), but it is SAFE — no
    # crash, no wrong styling — matching the trade-off this module already
    # accepts for `MAX_EMPHASIS_MARKERS`/`MAX_PARSEABLE_LENGTH`.
    #
    # Mutation-check: delete the `unsafe_escaped_delimiter_interaction?`
    # guard in `parse_lines`. Watched red: both examples below come back
    # styled (a single bold run, and a fully literal run respectively)
    # instead of matching `literal_lines(raw)` exactly.
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

    # Codex round 5 High: a SECOND escaped marker sitting between the
    # orphan and the real closing run used to get matched as next_run
    # itself (an escaped marker is always exactly one character, so it
    # always looked "safe") and masked the real, mismatched closer further
    # on. Verified directly against real marked before writing this: the
    # raw below renders as a fragmented, styled emphasis span, not literal
    # text; before this fix, unsafe_escaped_delimiter_interaction? returned
    # false here and parse_lines rendered fully unstyled text instead (not
    # even the safe fallback this guard exists to produce).
    #
    # Mutation-check: replace the gsub(...ESCAPED_CHARS, " ") in
    # unsafe_escaped_delimiter_interaction? with a no-op (search the raw
    # after substring directly). Watched red: this comes back styled
    # instead of matching literal_lines(raw).
    #
    # This example alone doesn't pin the gsub specifically — a guard
    # broadened to fire on ANY next_run (dropping the length-mismatch
    # check too) also passes it. It's the sibling example below ("does not
    # fall back when a lone orphan cleanly pairs with a same-length
    # closer") that catches that broader mutation; the two together pin
    # the real property, matching how every other example in this
    # `describe` block already covers one distinguishing shape rather than
    # standing alone.
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

    # Codex round 6 High, the OTHER half of the fix (`literal_lines` above
    # covers the marker-free fallback path; this covers the real kramdown
    # `Parser` path, reached only when `raw` contains a `*`/`_`, so it's a
    # genuinely different code path — the `:blank` case in `parse_lines`
    # itself). A blank-line paragraph gap between two `:p` blocks used to
    # push one empty `[]` line per blank `\n`; now it contributes none,
    # matching real mmdc's zero-margin paragraph CSS (`card[**A**\n\nB]`
    # renders `<p><strong>A</strong></p><p>B</p>` with the same single-line
    # advance as a plain hard break).
    #
    # Mutation-check: reinstate the pre-fix `:blank` handling
    # (`block.value.count("\n").times { lines << [] }`). Watched red: this
    # comes back with an extra `[]` line between the two runs instead of
    # the two lines concatenated directly.
    it 'collapses a blank-line paragraph gap to no extra lines on the real kramdown parse path' do
      lines = described_class.parse_lines("**A**\n\nB")

      expect(lines).to eq([
                            [described_class::Run.new(text: 'A', bold: true, italic: false)],
                            [described_class::Run.new(text: 'B', bold: false, italic: false)]
                          ])
    end

    # Codex round 6 High: kramdown's emphasis grammar disagrees with real
    # `marked` on these four short, valid labels — not just unstyled, but
    # WRONG (markers leak into the visible text, or inner markers vanish
    # when they should render literally). Verified directly against real
    # `marked.parseInline` before writing this:
    #   `****foo****`     -> marked <strong><strong>foo</strong></strong>
    #     (bold "foo", no markers); this module used to bold "**foo" and
    #     leave a trailing plain "**".
    #   `**foo* bar**`    -> marked <em><em>foo</em> bar</em>* (italic
    #     "foo bar", trailing literal *); this module used to bold
    #     "foo* bar" as one run.
    #   `_*a*_`           -> marked <em><em>a</em></em> (italic "a", no
    #     markers); this module used to italicize the literal text "*a*",
    #     markers included.
    #   `**foo **bar****` -> marked <strong>foo <strong>bar</strong></strong>
    #     (bold "foo bar", no markers); this module used to bold
    #     "foo **bar" and leave a trailing plain "**".
    # `unsafe_delimiter_run_structure?` falls back to `literal_lines` for
    # each of these rather than risk a wrong render — same trade-off as
    # `unsafe_escaped_delimiter_interaction?` above.
    #
    # Mutation-check: delete the `unsafe_delimiter_run_structure?` guard in
    # `parse_lines`. Watched red: all four come back styled (matching the
    # WRONG shapes quoted above) instead of `literal_lines(raw)`.
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
    # SEQUENTIAL pair -- one span's close immediately followed by the next
    # span's open -- is a different, already-safe shape and must not be
    # routed to literal_lines. Verified directly against real `marked`:
    # `*a*_b_` -> <em>a</em><em>b</em> (independent italics, no
    # cross-interaction); `_a_*b*` likewise. An earlier, cruder
    # adjacency-only version of Guard C false-positived on exactly these two
    # during development.
    #
    # Mutation-check: broaden `nested_delimiter_wrap?` to match ANY
    # `_(?!_)\*(?!\*)`/`\*(?!\*)_(?!_)` adjacency, dropping the `.*?` +
    # mirrored-close requirement. Watched red: both examples below fall back
    # to `literal_lines` instead of parsing as two independent styled runs.
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
  end

  describe '.build_markdown_tspans' do
    # Codex round 6 High: a blank-line paragraph gap used to shift the
    # following line down by one extra line-height per blank `\n`
    # ("Title\n\nSubtitle" used to carry a 2.4em dy — one line-height for
    # the blank plus one for the real advance). Verified directly against
    # real mmdc: `card[Title\n\nSubtitle]` renders `<p>Title</p><p>Subtitle</p>`
    # with zero paragraph margin, i.e. exactly the same single-line advance
    # as a plain hard break — `card[Title\nSubtitle]` renders identically.
    # `parse_lines` no longer produces an intervening empty runs array for
    # any number of blank lines (see `literal_lines`), so this exercises
    # both the producer and `build_markdown_tspans` together.
    #
    # Mutation-check: reinstate the pre-fix `literal_lines`
    # (`raw.split("\n", -1)` with no paragraph collapsing) — watched red,
    # dy comes back as `2.4em` instead of `1.2em`.
    it 'advances by exactly one line-height across a blank-line gap, however many blank lines' do
      one_blank = described_class.build_markdown_tspans(described_class.parse_lines("Title\n\nSubtitle"), x: 5)
      two_blank = described_class.build_markdown_tspans(described_class.parse_lines("A\n\n\nB"), x: 5)

      expect(one_blank.map { |t| [t.content, t.dy] }).to eq([['Title', nil], ['Subtitle', '1.2em']])
      expect(two_blank.map { |t| [t.content, t.dy] }).to eq([['A', nil], ['B', '1.2em']])
    end
  end
end
