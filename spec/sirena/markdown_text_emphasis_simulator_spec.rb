# frozen_string_literal: true

require "spec_helper"

module EmphasisSimulatorHelpers
  def runs(text)
    simulator.simulate(text).map { |r| [r.text, r.bold, r.italic] }
  end
end

RSpec.describe Sirena::MarkdownText do
  include EmphasisSimulatorHelpers

  # The simulator is a private constant of MarkdownText; const_get reaches it.
  let(:simulator) { described_class.const_get(:EmphasisSimulator) }

  describe ".char_class" do
    {
      nil => :boundary, " " => :space, "\t" => :space,
      "." => :punct, "$" => :punct,
      "a" => :word, "7" => :word, "é" => :word
    }.each do |char, expected|
      it "classifies #{char.inspect} as #{expected}" do
        expect(simulator.char_class(char)).to eq(expected)
      end
    end
  end

  describe ".alnum?" do
    it "is false for nil, punctuation and space, true for letters and digits" do
      results = [nil, ".", " ", "a", "9"].map { |c| simulator.alnum?(c) }
      expect(results).to eq([false, false, false, true, true])
    end
  end

  describe ".classify_ast" do
    {
      %i[punct space] => :close, %i[punct boundary] => :close,
      %i[word punct] => :close, %i[word space] => :close,
      %i[word boundary] => :close, %i[punct word] => :skip,
      %i[space word] => :skip, %i[space punct] => :skip,
      %i[punct punct] => :tight, %i[word word] => :tight,
      %i[space space] => :none, %i[boundary word] => :none
    }.each do |(prefix, suffix), expected|
      it "classifies #{prefix} then #{suffix} as #{expected}" do
        expect(simulator.classify_ast(prefix, suffix)).to eq(expected)
      end
    end
  end

  describe ".classify_und" do
    {
      %i[punct space] => :close, %i[word punct] => :close,
      %i[word boundary] => :close, %i[punct word] => :skip,
      %i[space word] => :skip, %i[space punct] => :skip,
      %i[punct punct] => :tight, %i[word word] => :none,
      %i[space space] => :none
    }.each do |(prefix, suffix), expected|
      it "classifies #{prefix} then #{suffix} as #{expected}" do
        expect(simulator.classify_und(prefix, suffix)).to eq(expected)
      end
    end
  end

  describe ".open_gate_ok?" do
    it "passes when the suffix is not punctuation" do
      expect(simulator.open_gate_ok?(false, "a")).to be(true)
    end

    it "passes at the start of the text" do
      expect(simulator.open_gate_ok?(true, nil)).to be(true)
    end

    it "passes after space or punctuation other than a marker" do
      expect([" ", "("].map do |c|
        simulator.open_gate_ok?(true, c)
      end).to eq([true, true])
    end

    it "refuses after a marker character or a word character" do
      expect(["*", "_", "a"].map do |c|
        simulator.open_gate_ok?(true, c)
      end).to eq([false, false, false])
    end
  end

  describe ".simulate" do
    {
      "**bold**" => [["bold", true, false]],
      "*it*" => [["it", false, true]],
      "__b__" => [["b", true, false]],
      "_i_" => [["i", false, true]],
      "***both***" => [["both", true, true]],
      "*foo*bar" => [["foo", false, true], ["bar", false, false]],
      "**foo**bar" => [["foo", true, false], ["bar", false, false]],
      "a_b_c" => [["a_b_c", false, false]],
      "_a_b" => [["_a_b", false, false]],
      "* foo*" => [["* foo*", false, false]],
      "**" => [["**", false, false]],
      "***" => [["***", false, false]],
      "x*" => [["x*", false, false]],
      "**a*" => [["*", false, false], ["a", false, true]],
      "*a **b** c*" => [["a ", false, true], ["b", true, true],
                        [" c", false, true]],
      "\\*a\\*" => [["*a*", false, false]],
      "*a\\**" => [["a*", false, true]],
      "*(a)*" => [["(a)", false, true]],
      "(*a*)" => [["(", false, false], ["a", false, true], [")", false, false]],
      "_(a)_" => [["(a)", false, true]],
      "!*a*!" => [["!", false, false], ["a", false, true], ["!", false, false]],
      "*a*b*c*" => [["a", false, true], ["b", false, false],
                    ["c", false, true]],
      "__a*b__" => [["a*b", true, false]],
      "**a_b**" => [["a_b", true, false]],
      "_**_**" => [["_", false, false], ["_", true, false]],
      "plain" => [["plain", false, false]],
      "" => [],
    }.each do |text, expected|
      it "reads #{text.inspect}" do
        expect(runs(text)).to eq(expected)
      end
    end
  end
end
