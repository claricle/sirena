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
    # through the real kramdown-based path to actually exercise the fixed
    # `else` branch this comment describes.
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
    # what actually exercises `parse_lines`'s fixed block-level `else`
    # branch. Mutation-check: restore the `raise` in that branch. Watched
    # red: both examples raise instead of returning literal text. A trailing
    # UNFLANKED `*` (no closing partner) is required, not any marker: a
    # well-formed pair like `*word*` resolves to a real `:em` node even
    # inside this fallback shape (kramdown span-parses top-level fallback
    # text same as it would inside a `:p`), which fragments the single
    # source line into several sibling blocks — a real but separate
    # behavior this fix doesn't need to handle differently, since mermaid
    # itself gives none of this whitespace-leading shape any defined
    # rendering to begin with.
    it 'treats a tab-leading line with a marker as literal text via the real parse path' do
      lines = described_class.parse_lines("\tIndented Label*")

      expect(lines).to eq([[described_class::Run.new(text: "\tIndented Label*", bold: false, italic: false)]])
    end

    it 'treats a four-space-leading line with a marker as literal text via the real parse path' do
      lines = described_class.parse_lines('    Four spaces label*')

      expect(lines).to eq([[described_class::Run.new(text: '    Four spaces label*', bold: false, italic: false)]])
    end

    # Same fallback block, reached from a second line after a hard break
    # rather than the first line of the text — the blank line between "a"
    # and the tab-led "b" is what breaks kramdown's lazy paragraph
    # continuation (verified: a tab-led SECOND line with no intervening
    # blank stays inside the `:p` and never reaches this fallback at all).
    # The marker on "a*" keeps the whole raw string off the early-exit path
    # (see the two examples above) without touching the tab-led block itself.
    it 'treats a tab-leading line after a blank line as literal text, on its own line' do
      lines = described_class.parse_lines("a*\n\n\tb")

      expect(lines).to eq([
                            [described_class::Run.new(text: 'a*', bold: false, italic: false)],
                            [],
                            [described_class::Run.new(text: "\tb", bold: false, italic: false)]
                          ])
    end

    # Guards the OTHER shape of "indented mid-label text": a four-space-led
    # line immediately continuing a paragraph (no blank line between) stays
    # inside kramdown's lazy `:p` continuation and never reaches the
    # fallback block at all — the embedded `\n` still becomes an ordinary
    # hard break, splitting into two lines exactly as it did before this
    # fix (the leading spaces on "b" are literal content, not consumed as
    # indentation, since no `:codeblock` parser is active to interpret them).
    it 'keeps an indented continuation line inside the paragraph, unaffected by the fallback' do
      lines = described_class.parse_lines("a\n    b")

      expect(lines).to eq([
                            [described_class::Run.new(text: 'a', bold: false, italic: false)],
                            [described_class::Run.new(text: '    b', bold: false, italic: false)]
                          ])
    end

    # Mutation-check: in `split_on_hard_breaks`, join `run.text.split("\n",
    # -1)`'s parts back together instead of starting a new line per part
    # (drop the `lines << [] if index.positive?`). Watched red: one
    # line/run with both sentences run together instead of two line-groups.
    it 'splits on a literal newline as a hard line break' do
      lines = described_class.parse_lines("Line one\nLine two")

      expect(lines).to eq([
                            [described_class::Run.new(text: 'Line one', bold: false, italic: false)],
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

    # Regression guard for a kramdown-specific DoS found while building
    # this rewrite: kramdown's `:emphasis` parser backtracks on ambiguous
    # markers at worse-than-quadratic cost (measured directly against
    # kramdown, bypassing this module: `"**_a " * n`, the worst pattern
    # found, costs ~1.25s aggregate across 300 cards at exactly
    # `MAX_PARSEABLE_LENGTH` each). No real card or column label with
    # actual markup in it is anywhere near `MAX_PARSEABLE_LENGTH`, so text
    # past it never reaches kramdown at all — mutation-check: delete the
    # length guard in `parse_lines`. Watched red: this example still
    # passes its length assertion but the run comes back split into
    # several styled bold runs instead of one literal one.
    #
    # Uses well-formed `**x** ` pairs, not ambiguous single markers: kramdown
    # never resolves `"*a " * 100` into any `:strong`/`:em` node even well
    # under the length cap (proven directly against `Parser` above), so that
    # shape can't tell "the fallback skipped kramdown" apart from "kramdown
    # ran and found nothing to style" — deleting the guard would leave this
    # example green for the wrong reason. `"**x** "` DOES parse into
    # `:strong` nodes under the cap, so only the guard being live explains a
    # single unstyled run here.
    it 'falls back to unstyled literal text past MAX_PARSEABLE_LENGTH, never parsing markup' do
      long_text = "**x** " * 10

      expect(long_text.length).to be > described_class::MAX_PARSEABLE_LENGTH

      lines = described_class.parse_lines(long_text)

      expect(lines).to eq([[described_class::Run.new(text: long_text, bold: false, italic: false)]])
    end

    # The fallback still respects hard line breaks — it skips kramdown,
    # not line-splitting. A leading `*` keeps this on the LENGTH guard
    # specifically rather than the marker-free early exit above.
    it 'still splits on hard line breaks in the unstyled fallback' do
      long_text = "*#{'x' * described_class::MAX_PARSEABLE_LENGTH}\nsecond"

      lines = described_class.parse_lines(long_text)

      expect(lines.last).to eq([described_class::Run.new(text: 'second', bold: false, italic: false)])
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

    # Boundary: markup exactly at the cap still gets parsed normally.
    it 'still parses markup at exactly MAX_PARSEABLE_LENGTH characters' do
      padding = "a" * (described_class::MAX_PARSEABLE_LENGTH - "**bold**".length)
      text = "**bold**#{padding}"
      expect(text.length).to eq(described_class::MAX_PARSEABLE_LENGTH)

      lines = described_class.parse_lines(text)

      expect(lines).to eq([[
                            described_class::Run.new(text: 'bold', bold: true, italic: false),
                            described_class::Run.new(text: padding, bold: false, italic: false)
                          ]])
    end
  end

  describe '.build_markdown_tspans' do
    # Mutation-check: this is the bug the fix closes. Before it, a blank
    # line (empty runs array) had no first run to hang its `dy` shift on,
    # so the shift was silently dropped instead of carried onto the next
    # line. Watched red: only one tspan comes back, with no `dy` at all.
    it "carries a blank line's height onto the next line instead of dropping it" do
      lines = described_class.parse_lines("Title\n\nSubtitle")

      tspans = described_class.build_markdown_tspans(lines, x: 5)

      expect(tspans.map { |t| [t.content, t.dy] }).to eq([
                                                           ['Title', nil],
                                                           ['Subtitle', '2.4em']
                                                         ])
    end

    # Two blank lines in a row accumulate to three line-heights, not one.
    it 'accumulates across more than one consecutive blank line' do
      lines = described_class.parse_lines("A\n\n\nB")

      tspans = described_class.build_markdown_tspans(lines, x: 5)

      expect(tspans.map { |t| [t.content, t.dy] }).to eq([
                                                           ['A', nil],
                                                           ['B', '3.6em']
                                                         ])
    end
  end
end
