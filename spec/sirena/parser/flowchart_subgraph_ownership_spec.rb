# frozen_string_literal: true

require "spec_helper"

# Which box owns a subgraph when more than one names it.
#
# mermaid arbitrates by source order and nothing else: the FIRST claim
# on an id keeps it. A claim is a box naming the id — as a bare
# reference, as an edge endpoint, or by declaring it inside itself. A
# declaration at the TOP level claims nothing, so it never blocks a
# later reference.
#
# Every expectation below was measured against mmdc 11.12.0 by rendering
# the source and reading containment off the SVG geometry — the smallest
# cluster rect that encloses each box — rather than off DOM nesting,
# which cannot separate a cluster's contents from its top-level
# siblings.
#
# The gap these do NOT pin: a box left holding nothing is drawn by mmdc
# as a plain node, and Sirena draws nothing. That predates this rule and
# is tracked separately.
RSpec.describe Sirena::Parser::FlowchartParser do
  # First box wins the id, the way the transform registers them. A
  # redeclaration pushes a second, empty box carrying the same id, so
  # keying last-wins would hand back the one that holds nothing.
  def boxes(source)
    all = described_class.new.parse(source).subgraphs
    all.each_with_object({}) { |box, held| held[box.id] ||= box }
  end

  describe "two boxes naming the same subgraph" do
    # The bug this rule was written for. `c` names `b` first, so `b` is
    # c's, and the later `subgraph b` written inside `a` does not take
    # it back. Ownership used to go to whichever declaration came last.
    it "gives it to a reference written before the declaration" do
      held = boxes("flowchart TD\nsubgraph c\nb\nend\n" \
                   "subgraph a\nsubgraph b\nX\nend\nend\n")

      expect(held["b"].parent_id).to eq("c")
      expect(held["a"]).not_to be_drawable
    end

    it "gives it to a declaration written before the reference" do
      held = boxes("flowchart TD\nsubgraph a\nsubgraph b\nX\nend\nend\n" \
                   "subgraph c\nb\nend\n")

      expect(held["b"].parent_id).to eq("a")
      expect(held["c"]).not_to be_drawable
    end

    it "gives it to the first of two references" do
      held = boxes("flowchart TD\nsubgraph c\nb\nend\nsubgraph d\nb\nend\n" \
                   "subgraph b\nX\nend\n")

      expect(held["b"].parent_id).to eq("c")
      expect(held["d"]).not_to be_drawable
    end

    # A second declaration still merges its body into the same box. It
    # loses the parentage, not the contents. Order is asserted because
    # it is source order — mmdc 11.12.0 lists X before Y too.
    it "gives it to the first of two declarations" do
      source = "flowchart TD\nsubgraph a\nsubgraph b\nX\nend\nend\n" \
               "subgraph c\nsubgraph b\nY\nend\nend\n"
      all = described_class.new.parse(source).subgraphs
      held = boxes(source)

      expect(held["b"].parent_id).to eq("a")
      expect(held["b"].node_ids).to eq(%w[X Y])
      # Both declarations, not just the winner: while the loser also took
      # the id, everything above stayed true and the theft went unseen.
      expect(all.select { |box| box.id == "b" }.map(&:parent_id))
        .to eq(["a", nil])
      expect(held["c"].child_ids).to be_empty
    end

    # Declaring a box at the top level claims nothing, so a nested
    # redeclaration afterwards is its FIRST claim and takes it. The
    # parent has to land on the box that HOLDS the contents, not on the
    # empty second object the redeclaration built — parenting that one
    # drew `a` and `b` side by side where mmdc nests them.
    it "parents the box that holds the contents, not the redeclaration" do
      source = "flowchart TD\nsubgraph b\nX\nend\n" \
               "subgraph a\nsubgraph b\nY\nend\nend\n"
      diagram = described_class.new.parse(source)
      held = boxes(source)
      drawn = diagram.subgraphs.select(&:drawable?)

      expect(held["b"].parent_id).to eq("a")
      expect(held["b"].node_ids).to eq(%w[X Y])
      expect(held["a"].child_ids).to eq(%w[b])
      # The one that gets drawn is the one that got the parent. The
      # empty duplicate is left unparented and filtered out.
      expect(drawn.map { |box| [box.id, box.parent_id] })
        .to contain_exactly(["b", "a"], ["a", nil])
    end

    # The same shape with a reference after it, and one with two
    # top-level declarations first. Order permutations, because a rule
    # measured on one order is the defect that produced this example.
    it "keeps the holder parented however the redeclarations are ordered" do
      {
        "top, nested, reference" =>
          "flowchart TD\nsubgraph b\nX\nend\nsubgraph a\nsubgraph b\n" \
          "Y\nend\nend\nsubgraph c\nb\nend\n",
        "top, top, nested" =>
          "flowchart TD\nsubgraph b\nX\nend\nsubgraph b\nY\nend\n" \
          "subgraph a\nsubgraph b\nZ\nend\nend\n",
        "nested, top" =>
          "flowchart TD\nsubgraph a\nsubgraph b\nX\nend\nend\n" \
          "subgraph b\nY\nend\n"
      }.each do |order, source|
        held = boxes(source)

        aggregate_failures(order) do
          expect(held["b"].parent_id).to eq("a")
          expect(held["b"]).to be_drawable
          expect(held["a"].child_ids).to eq(%w[b])
        end
      end
    end

    # Stated rather than hidden behind the helper: the losing
    # declaration leaves a second, empty box carrying the same id in the
    # collection. Nothing draws it — `drawable_subgraphs` filters it
    # before the layout sees it — but a caller keying `subgraphs` by id
    # last-wins would pick up the wrong one. It predates this rule.
    it "leaves the losing declaration as an undrawable duplicate" do
      source = "flowchart TD\nsubgraph a\nsubgraph b\nX\nend\nend\n" \
               "subgraph c\nsubgraph b\nY\nend\nend\n"
      all = described_class.new.parse(source).subgraphs.select do |box|
        box.id == "b"
      end

      expect(all.size).to eq(2)
      expect(all.map(&:drawable?)).to eq([true, false])
      # The half that pins ownership: the loser took no parent, so it is
      # not hanging off `c` and `c` is not holding it.
      expect(all.last.parent_id).to be_nil
    end

    # An id standing at the end of an arrow claims just as a bare one
    # does, so the box holding the edge owns the subgraph it names.
    it "counts an edge endpoint as a claim" do
      held = boxes("flowchart TD\nsubgraph c\nb --> z\nend\n" \
                   "subgraph b\nX\nend\n")

      expect(held["b"].parent_id).to eq("c")
      expect(held["c"].node_ids).to eq(%w[z])
      expect(held["c"].child_ids).to eq(%w[b])
    end

    # A box declared at the top level has no parent to claim it, so a
    # reference written afterwards still wins it.
    it "lets a later reference take a box declared at the top level" do
      held = boxes("flowchart TD\nsubgraph b\nX\nend\nsubgraph c\nb\nend\n")

      expect(held["b"].parent_id).to eq("c")
    end

    it "resolves a chain of references in source order" do
      held = boxes("flowchart TD\nsubgraph c\nb\nend\nsubgraph b\na\nend\n" \
                   "subgraph a\nX\nend\n")

      expect(held["b"].parent_id).to eq("c")
      expect(held["a"].parent_id).to eq("b")
    end
  end

  # A cycle is judged on who ACTUALLY ends up holding what, not on what
  # the source writes. A claim that loses makes no edge, so a loop drawn
  # on paper by a losing claim is not a loop at all. Walking the written
  # source instead refused diagrams mmdc draws.
  describe "a loop that only the losing claims would close" do
    # `c` takes `b` first. `b` then takes `a`. `a` finally names `b`,
    # which is already spoken for, so that claim loses and closes
    # nothing. Measured on mmdc 11.12.0: clusters `c` and `b`, with `a`
    # drawn as a plain node inside `b`.
    it "takes a source whose last claim loses" do
      source = "flowchart TD\nsubgraph c\nb\nend\n" \
               "subgraph b\na\nend\nsubgraph a\nb\nend\n"
      diagram = described_class.new.parse(source)
      held = diagram.subgraphs.each_with_object({}) do |box, acc|
        acc[box.id] ||= box
      end

      expect(held["b"].parent_id).to eq("c")
      expect(held["b"].node_ids).to eq(%w[a])
      expect(held["a"]).not_to be_drawable
      # Not merely undrawable: mmdc draws `a` as a plain node in `b`,
      # and it survives as one here because `b` holds its id.
      expect(diagram.nodes.map(&:id)).to eq(%w[a])
    end

    # The same loop with the losing claim written earlier.
    it "takes it wherever the losing claim sits" do
      source = "flowchart TD\nsubgraph c\nb\nend\n" \
               "subgraph a\nb\nend\nsubgraph b\na\nend\n"
      held = boxes(source)

      expect(held["b"].parent_id).to eq("c")
      expect(held["b"].node_ids).to eq(%w[a])
      expect(held["a"]).not_to be_drawable
    end

    # Declarations claim exactly as references do, so a loop written by
    # nesting is caught by the same edge set. `named_ids` used to
    # collect these separately; nothing does now, so it needs its own
    # example. mmdc refuses this source too.
    it "still refuses a loop closed by nested declarations" do
      source = "flowchart TD\nsubgraph a\nsubgraph b\nX\nend\nend\n" \
               "subgraph b\nsubgraph a\nY\nend\nend\n"

      expect { described_class.new.parse(source) }
        .to raise_error(Sirena::Parser::ParseError,
                        /Setting b as parent of a would create a cycle/)
    end

    # And the guard still fires when the claims all WIN. Proving it in
    # one direction only would let the check rot into never refusing.
    it "still refuses a loop every claim wins" do
      source = "flowchart TD\nsubgraph a\nb\nend\nsubgraph b\na\nend\n"

      expect { described_class.new.parse(source) }
        .to raise_error(Sirena::Parser::ParseError,
                        /Setting b as parent of a would create a cycle/)
    end

    it "still refuses a ring of four" do
      source = "flowchart TD\nsubgraph a\nb\nend\nsubgraph b\nc\nend\n" \
               "subgraph c\nd\nend\nsubgraph d\na\nend\n"

      expect { described_class.new.parse(source) }
        .to raise_error(Sirena::Parser::ParseError,
                        /Setting d as parent of a would create a cycle/)
    end

    # A ring anywhere refuses the whole diagram, even with a perfectly
    # good box beside it. Measured: mmdc rejects this source too.
    it "still refuses a ring beside a box that would have drawn" do
      source = "flowchart TD\nsubgraph a\nb\nend\nsubgraph b\na\nend\n" \
               "subgraph z\nQ\nend\n"

      expect { described_class.new.parse(source) }
        .to raise_error(Sirena::Parser::ParseError,
                        /Setting b as parent of a would create a cycle/)
    end
  end

  describe "an edge naming a box that a later declaration used to steal" do
    # `c` holds `b`, so `c` is worth drawing and the edge reaches it.
    # While the later declaration won, `c` was left empty and its own id
    # had to survive as a loose node instead.
    it "reaches the box that claimed the reference" do
      source = "flowchart TD\nsubgraph c\nb\nend\n" \
               "subgraph a\nsubgraph b\nX\nend\nend\nc --> Z\n"
      diagram = described_class.new.parse(source)
      held = diagram.subgraphs.to_h { |box| [box.id, box] }

      expect(held["c"].child_ids).to eq(%w[b])
      expect(held["b"].node_ids).to eq(%w[X])
      expect(diagram.nodes.map(&:id)).to eq(%w[X Z])
      expect(diagram.edges.map { |e| [e.source_id, e.target_id] })
        .to eq([%w[c Z]])
      expect(diagram).to be_valid
    end

    # One level further out: `d` names `c`, `c` names `b`, and each
    # first claim holds all the way down.
    it "keeps the whole chain when the reference is nested" do
      source = "flowchart TD\nsubgraph d\nc\nend\nsubgraph c\nb\nend\n" \
               "subgraph a\nsubgraph b\nX\nend\nend\nc --> Z\n"
      held = boxes(source)

      expect(held["c"].parent_id).to eq("d")
      expect(held["b"].parent_id).to eq("c")
      expect(held["a"]).not_to be_drawable
    end
  end
end
