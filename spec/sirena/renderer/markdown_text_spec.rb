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
