# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Diagram::SequenceText do
  describe ".display" do
    it "removes a leading wrap directive case-insensitively" do
      cases = {
        "wrap:hello" => "hello",
        "nowrap:hello" => "hello",
        "  wrap:  hello" => "hello",
        "NoWrAp:hello" => "hello",
        "hello wrap:world" => "hello wrap:world",
      }

      actual = cases.keys.to_h do |input|
        [input, described_class.display(input)]
      end

      expect(actual).to eq(cases)
    end

    it "normalizes supported HTML break spellings" do
      inputs = ["one<br>two", "one<br/>two", "one<BR />two"]
      actual = inputs.map { |input| described_class.display(input) }

      expect(actual).to eq(["one two"] * 3)
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
