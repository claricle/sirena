# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/sequence"

# Labels measured with mmdc: quotes stay part of the alias text.
module SequenceAliasQuoteHelpers
  def label_of(declaration)
    source = "sequenceDiagram\n#{declaration}\nA->>B: hi\n"
    described_class.new.parse(source).find_participant("A").label
  end
end

RSpec.describe Sirena::Parser::Sequence do
  include SequenceAliasQuoteHelpers

  {
    "participant A as \"x\"" => "\"x\"",
    "participant A as 'x y'" => "'x y'",
    "participant A as \"a \"b\" c\"" => "\"a \"b\" c\"",
    "participant A as \"x\" y" => "\"x\" y",
    "participant A as \"\"" => "\"\"",
    "actor A as \"x\"" => "\"x\"",
    "participant A as x\"y" => "x\"y",
  }.each do |declaration, expected|
    it "keeps the quotes of #{declaration.inspect}" do
      expect(label_of(declaration)).to eq(expected)
    end
  end

  it "still ends an alias at an inline semicolon" do
    expect(label_of("participant A as x;")).to eq("x")
  end
end
