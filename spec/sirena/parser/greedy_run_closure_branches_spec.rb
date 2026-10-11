# frozen_string_literal: true

require "spec_helper"
require "parslet"
require "sirena/parser/atoms/greedy_run"

RSpec.describe Sirena::Parser::Atoms::GreedyRun do
  # ascii_prefix is private and only reached after an encoding clash on a
  # chunk that holds a high byte; an all-ASCII chunk is called directly.
  describe ".ascii_prefix" do
    it "keeps a chunk with no high byte whole" do
      expect(described_class.send(:ascii_prefix, "abc")).to eq("abc")
    end

    it "cuts a chunk at its first high byte" do
      expect(described_class.send(:ascii_prefix, "ab\xC3\xA9c".b)).to eq("ab".b)
    end
  end
end
