# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Diagram::SequenceText do
  describe ".display" do
    {
      "wrap:hello" => "hello",
      "nowrap:hello" => "hello",
      "  wrap:  hello" => "hello",
      "NoWrAp:hello" => "hello",
      "hello wrap:world" => "hello wrap:world",
    }.each do |input, expected|
      it "shows #{input.inspect} as #{expected.inspect}" do
        expect(described_class.display(input)).to eq(expected)
      end
    end

    {
      "one<br>two" => "one two",
      "one<br/>two" => "one two",
      "one<BR />two" => "one two",
    }.each do |input, expected|
      it "normalizes the break in #{input.inspect}" do
        expect(described_class.display(input)).to eq(expected)
      end
    end

    it "decodes a numeric entity" do
      expect(described_class.display("#9829;")).to eq("♥")
    end

    it "decodes known named entities" do
      input = "#infin; #hearts; #amp; #lt; #gt; #quot; #nbsp;"

      expect(described_class.display(input)).to eq("∞ ♥ & < > \"  ")
    end

    it "preserves an unknown named entity" do
      expect(described_class.display("#unknown;")).to eq("#unknown;")
    end
  end
end
