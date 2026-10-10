# frozen_string_literal: true

require "spec_helper"

module MarkdownTextRendererSpecHelpers
  def tspan_summary(source)
    lines = Sirena::MarkdownText.parse_lines(source)
    tspans = Sirena::Renderer::MarkdownText.build_markdown_tspans(lines, x: 5)
    tspans.map { |tspan| [Array(tspan.content).join, tspan.line_shift] }
  end
end

RSpec.describe Sirena::Renderer::MarkdownText do
  include MarkdownTextRendererSpecHelpers

  describe ".assign_markdown_text" do
    it "renders an empty parsed label as an empty text element" do
      lines = Sirena::MarkdownText.parse_lines("")
      text = Sirena::Svg::Text.new

      described_class.assign_markdown_text(text, lines, x: 5)

      expect([lines, text.to_xml]).to eq([[[]], "<text></text>"])
    end
  end

  describe ".build_markdown_tspans" do
    # A blank-line paragraph gap must not shift the following line down by
    # one extra line-height per blank `\n` — real mmdc renders zero
    # paragraph margin, the same single-line advance as a plain hard
    # break. `Sirena::MarkdownText.parse_lines` must not produce an
    # intervening empty runs array for any number of blank lines, so this
    # exercises both the producer and `build_markdown_tspans` together.
    it "advances by exactly one line-height across a blank-line gap, " \
       "however many blank lines" do
      # `content` is `collection: true`, so read it through Array(...).
      expect([tspan_summary("Title\n\nSubtitle"), tspan_summary("A\n\n\nB")])
        .to eq([[["Title", nil], ["Subtitle", 1]],
                [["A", nil], ["B", 1]]])
    end
  end
end
