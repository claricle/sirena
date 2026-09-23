# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::Renderer::MarkdownText do
  describe '.build_markdown_tspans' do
    # A blank-line paragraph gap must not shift the following line down by
    # one extra line-height per blank `\n` — real mmdc renders zero
    # paragraph margin, the same single-line advance as a plain hard
    # break. `Sirena::MarkdownText.parse_lines` must not produce an
    # intervening empty runs array for any number of blank lines, so this
    # exercises both the producer and `build_markdown_tspans` together.
    it 'advances by exactly one line-height across a blank-line gap, however many blank lines' do
      one_blank = described_class.build_markdown_tspans(Sirena::MarkdownText.parse_lines("Title\n\nSubtitle"), x: 5)
      two_blank = described_class.build_markdown_tspans(Sirena::MarkdownText.parse_lines("A\n\n\nB"), x: 5)

      expect(one_blank.map { |t| [svg_text_content(t), t.dy] }).to eq([['Title', nil], ['Subtitle', '1.2em']])
      expect(two_blank.map { |t| [svg_text_content(t), t.dy] }).to eq([['A', nil], ['B', '1.2em']])
    end
  end
end
