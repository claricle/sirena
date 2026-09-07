# frozen_string_literal: true

require "benchmark"
require "spec_helper"

# Speed and size, kept apart from the correctness suite.
#
# Every example here either reads the clock or builds a fixture with
# thousands of boxes in it, so each one is slow and each one can fail on
# a busy machine without anything being wrong with the code. Mixed in
# with the ordinary specs they made a normal run take fifteen seconds
# and go red for reasons a reader could do nothing about.
#
# Run them with `rake benchmark`, which is part of the default `rake`
# task, so CI still guards every regression named below. `rspec` on its
# own does not pick this file up: the name does not end in `_spec.rb`.
RSpec.describe Sirena::Parser::FlowchartParser do
  def boxes(source)
    described_class.new.parse(source).subgraphs
  end

  # A title carrying a run of spaces parsed in quadratic time: the old rule
  # re-ran its terminator test at every byte, and each test rescanned the
  # whole run. 4k spaces took 3.7 seconds on a source mmdc renders.
  describe "a long title" do
    it "parses in linear time" do
      source = "graph TD\nsubgraph s #{' ' * 8000}Title\nA\nend\n"

      elapsed = Benchmark.realtime { described_class.new.parse(source) }

      expect(elapsed).to be < 1.0
    end
  end

  # A box holds everything below it, not just its own line, so the
  # containment graph is a transitive closure. Walking it with a
  # path-local visited list re-entered every box once per route into it,
  # and the cost doubled per box: 22 took 8 seconds, 24 took fifty, and
  # the 220 mmdc draws would never have come back.
  describe "a deeply nested diagram" do
    it "checks for a cycle without re-walking every route" do
      nested = (0...22).map { |i| "subgraph s#{i}\n" }.join
      source = "graph TD\n#{nested}A-->B\n#{"end\n" * 22}"

      elapsed = Benchmark.realtime { described_class.new.parse(source) }

      expect(elapsed).to be < 1.0
    end
  end

  # Claiming a member went through the model's collection setter once per
  # node, which copies the whole array every time. Measured against the
  # same nodes at the top level, because that is the same parse without
  # the claiming — the machine cancels out and the quadratic term does
  # not. The ratio was 3.6 before and sits under 1 now.
  describe "a subgraph holding many nodes" do
    it "costs no more than the same nodes outside one" do
      body = (0...1600).map { |i| "n#{i}" }.join("\n")
      loose = Benchmark.realtime { described_class.new.parse("graph TD\n#{body}\n") }
      boxed = Benchmark.realtime do
        described_class.new.parse("graph TD\nsubgraph s [T]\n#{body}\nend\n")
      end

      expect(boxed).to be < loose * 2
    end
  end

  # A flat chain nests nothing, so the grammar's own depth guard never
  # fires. The ownership walk recursed anyway and raised a bare
  # SystemStackError straight out of the parse.
  #
  # The chain it built, not just "it did not raise": with the cycle check
  # replaced by `nil` this source still parses cleanly, so the bare form
  # said nothing about cycles despite its name. Fifteen other examples
  # fail on that mutation; what is left to pin here is the flat walk.
  #
  # Four thousand boxes, because the point is a chain no recursive walk
  # could survive. The short chain in the spec file pins the shape.
  describe "a long chain of boxes" do
    it "walks the whole chain without recursing" do
      chain = (0...4_000).map { |i| "subgraph s#{i}\ns#{i + 1}\nend\n" }.join
      built = boxes("graph TD\n#{chain}s4000\n")
      last = built.last

      expect([built.size, last.id, last.parent_id, last.node_ids])
        .to eq([4000, "s3999", "s3998", %w[s4000]])
    end
  end
end
