# frozen_string_literal: true

require "spec_helper"
require "kramdown"

RSpec.describe Sirena::MarkdownText do
  # The span parsers are restricted to emphasis and escapes, so no label
  # reaches flatten_child with another span type; the module function is
  # called directly with a hand-built kramdown element.
  describe ".flatten_child" do
    let(:element) { Kramdown::Element }

    it "degrades an unknown span with a string value to literal text" do
      runs = described_class.flatten_child(
        element.new(:codespan, "x"), bold: true, italic: false
      )

      expect(runs.map { |run| [run.text, run.bold, run.italic] })
        .to eq([["x", true, false]])
    end

    it "joins the literal text of an unknown span that only has children" do
      span = element.new(:a)
      span.children << element.new(:text, "q") << element.new(:codespan, "r")
      runs = described_class.flatten_child(span, bold: false, italic: true)

      expect(runs.map { |run| [run.text, run.bold, run.italic] })
        .to eq([["qr", false, true]])
    end
  end

  describe ".parse_lines" do
    it "breaks lines at a bare newline between two styled spans" do
      lines = described_class.parse_lines("**a**\n**b**")

      expect(lines.map { |line| line.map(&:text) }).to eq([["a"], ["b"]])
    end
  end
end
