# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Diagram::SequenceText do
  describe ".display" do
    let(:wrap_cases) do
      {
        "wrap:hello" => "hello",
        "nowrap:hello" => "hello",
        "  wrap:  hello" => "hello",
        "NoWrAp:hello" => "hello",
        "hello wrap:world" => "hello wrap:world",
      }
    end

    it "removes a leading wrap directive case-insensitively" do
      actual = wrap_cases.keys.to_h do |input|
        [input, described_class.display(input)]
      end

      expect(actual).to eq(wrap_cases)
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

      expect(described_class.display(input)).to eq("∞ ♥ & < > \" \u00A0")
    end

    it "keeps an unknown name as the literal &name; mermaid draws" do
      expect(described_class.display("#unknown;")).to eq("&unknown;")
    end
  end

  describe ".decode" do
    {
      "#59;" => ";", "#0065;" => "A", "#35;59;" => "#59;",
      "#x41;" => "&x41;", "#AMP;" => "&", "#Amp;" => "&Amp;",
      "#amp;lt;" => "&lt;", "#128;" => "\u20AC", "#0;" => "\uFFFD",
      "#55296;" => "\uFFFD", "#1114112;" => "\uFFFD",
      "a # b; c" => "a # b; c"
    }.each do |input, expected|
      it "decodes #{input.inspect} like mmdc" do
        expect(described_class.decode(input)).to eq(expected)
      end
    end
  end
end
