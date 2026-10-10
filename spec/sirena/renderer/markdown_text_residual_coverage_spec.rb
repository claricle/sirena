# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::MarkdownText do
  describe ".build_markdown_tspans" do
    let(:lines) do
      top = Sirena::MarkdownText::Run.new(
        text: "Top", bold: false, italic: false,
      )
      bottom = Sirena::MarkdownText::Run.new(
        text: "Bottom", bold: false, italic: false,
      )
      [[top], [], [bottom]]
    end

    it "retains the line distance across an explicit empty run-line" do
      tspans = described_class.build_markdown_tspans(lines, x: 7)
      evidence = tspans.map do |tspan|
        [Array(tspan.content).join, tspan.x, tspan.line_shift]
      end

      expect(evidence).to eq([["Top", nil, nil], ["Bottom", 7.0, 2]])
    end

    it "requires the horizontal anchor" do
      run = Sirena::MarkdownText::Run.new(
        text: "Label", bold: false, italic: false,
      )

      expect { described_class.build_markdown_tspans([[run]]) }
        .to raise_error(ArgumentError, "missing keyword: :x")
    end
  end
end
