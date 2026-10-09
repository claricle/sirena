# frozen_string_literal: true

require "spec_helper"

module ParseLinesHelpers
  def flat(text)
    Sirena::MarkdownText.parse_lines(text).map do |line|
      line.map { |run| [run.text, run.bold, run.italic] }
    end
  end
end

RSpec.describe Sirena::MarkdownText do
  include ParseLinesHelpers

  [
    ["a binary-tagged string", "**a**".b, [[["a", true, false]]]],
    ["leading blank paragraphs", "\n\nx", [[["x", false, false]]]],
    ["a trailing newline", "a\n", [[["a", false, false]], []]],
    ["a run of blank lines between paragraphs", "a\n\n\nb",
     [[["a", false, false]], [["b", false, false]]]],
    ["an escaped non-emphasis character beside emphasis", "\\# *a*",
     [[["# ", false, false], ["a", false, true]]]],
    ["an escaped asterisk beside emphasis", "\\* *a*",
     [[["* ", false, false], ["a", false, true]]]],
    ["blank lines between two styled paragraphs", "**a**\n\n\n*b*",
     [[["a", true, false]], [["b", false, true]]]],
    ["a trailing space before a break", "**a** \nb",
     [[["a", true, false], [" ", false, false]], [["b", false, false]]]],
    ["an unterminated span split by a blank line", "**a\n\nb**",
     [[["**a", false, false]], [["b**", false, false]]]],
    ["a code span", "x `*y*` **z**",
     [[["x `", false, false], ["y", false, true],
       ["` ", false, false], ["z", true, false]]]],
    ["raw html after bold", "**a** <b>q</b>",
     [[["a", true, false], [" <b>q</b>", false, false]]]],
    ["a whitespace-only line", "**a**\n  \nb",
     [[["**a**", false, false]], [["  ", false, false]],
      [["b", false, false]]]],
    ["an entity after italic", "*a*&amp;",
     [[["a", false, true], ["&amp;", false, false]]]],
    ["a link-looking span", "[l](u) **a**",
     [[["[l](u) ", false, false], ["a", true, false]]]],
  ].each do |name, input, expected|
    it "parses #{name}" do
      expect(flat(input)).to eq(expected)
    end
  end
end
