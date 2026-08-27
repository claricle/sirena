# frozen_string_literal: true

require "spec_helper"

# The module is shared by two callers whose graphs run in OPPOSITE
# directions — the parser passes id-to-what-it-holds, the model passes
# id-to-its-parent — so what is pinned here is that it reads edges and
# says nothing about parentage. Get that wrong and one of the two
# callers is documented backwards.
RSpec.describe Sirena::Diagram::Containment do
  describe ".looping_pair" do
    it "finds nothing in an empty graph" do
      expect(described_class.looping_pair({})).to be_nil
    end

    it "finds nothing in a chain" do
      expect(described_class.looping_pair({ "a" => %w[b], "b" => %w[c] }))
        .to be_nil
    end

    it "finds nothing when two branches meet again" do
      graph = { "a" => %w[b c], "b" => %w[d], "c" => %w[d] }

      expect(described_class.looping_pair(graph)).to be_nil
    end

    it "names both ends of a one-box loop" do
      expect(described_class.looping_pair({ "s" => %w[s] })).to eq(%w[s s])
    end

    it "names both ends of a two-box loop" do
      expect(described_class.looping_pair({ "a" => %w[b], "b" => %w[a] }))
        .to eq(%w[b a])
    end

    it "finds a loop that closes three boxes later" do
      graph = { "p" => %w[q], "q" => %w[r], "r" => %w[p] }

      expect(described_class.looping_pair(graph)).to eq(%w[r p])
    end

    # The model's graph points the other way, and the answer has to be
    # the same. Only the reading of the returned pair differs.
    it "reads a parent graph the same as a containment graph" do
      holds = { "outer" => %w[inner] }
      parents = { "inner" => %w[outer] }

      expect(described_class.looping_pair(holds)).to be_nil
      expect(described_class.looping_pair(parents)).to be_nil
    end

    it "ignores an edge to an id that is not a key" do
      expect(described_class.looping_pair({ "s" => %w[absent] })).to be_nil
    end

    # A flat chain of 4,000 is a source mmdc draws, and the recursive
    # form raised SystemStackError out of the parse.
    it "walks a chain far deeper than the stack allows" do
      graph = (0...4000).to_h { |i| ["b#{i}", ["b#{i + 1}"]] }

      expect(described_class.looping_pair(graph)).to be_nil
    end

    it "still finds a loop at the end of a very long chain" do
      graph = (0...4000).to_h { |i| ["b#{i}", ["b#{i + 1}"]] }
      graph["b4000"] = %w[b0]

      expect(described_class.looping_pair(graph)).to eq(%w[b4000 b0])
    end

    it "keeps back_edge off the public surface" do
      expect { described_class.back_edge({}, "x", {}) }
        .to raise_error(NoMethodError)
    end
  end
end
