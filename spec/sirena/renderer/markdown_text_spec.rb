# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::Renderer::MarkdownText do
  describe '.parse_lines' do
    # Mutation-check: remove the `**` branch from the recursive scan
    # (`marker_at` returning BOLD). Watched red: the run comes back plain
    # (`bold: false`) instead of bold, and the literal `**` characters
    # reappear in its text.
    it 'renders **bold** as one bold run' do
      lines = described_class.parse_lines('**bold**')

      expect(lines).to eq([[described_class::Run.new(text: 'bold', bold: true, italic: false)]])
    end

    # Mutation-check: remove the `*` branch from `marker_at`. Watched red:
    # the run comes back plain instead of italic.
    it 'renders *italic* as one italic run' do
      lines = described_class.parse_lines('*italic*')

      expect(lines).to eq([[described_class::Run.new(text: 'italic', bold: false, italic: true)]])
    end

    # Mutation-check: pass the outer flags straight through the recursive
    # call instead of merging them with `||` (i.e. `bold: marker == BOLD`
    # rather than `bold: bold || marker == BOLD`). Watched red: the middle
    # run loses `bold` and comes back italic-only.
    it 'nests bold and italic, merging flags rather than overriding them' do
      lines = described_class.parse_lines('**bold *and italic* end**')

      expect(lines).to eq([[
                            described_class::Run.new(text: 'bold ', bold: true, italic: false),
                            described_class::Run.new(text: 'and italic', bold: true, italic: true),
                            described_class::Run.new(text: ' end', bold: true, italic: false)
                          ]])
    end

    # Mutation-check: remove the `flanked_open?`/`flanked_close?` guards
    # (always return true). Watched red: each case below closes into a
    # styled run instead of staying one literal plain run.
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

    # Mutation-check: remove the `"\n"` split in `parse_lines` (parse the
    # whole text as one line). Watched red: one line/run with both
    # sentences run together instead of two line-groups.
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
