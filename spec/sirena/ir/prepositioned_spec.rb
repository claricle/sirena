# frozen_string_literal: true

require "spec_helper"
require "sirena/ir"

RSpec.describe Sirena::IR::Prepositioned do
  def scalar(number)
    Sirena::IR::Scalar.new(number: number)
  end

  def placement(dimension, ordinal, number)
    Sirena::IR::Placement.new(
      dimension: dimension, ordinal: ordinal, value: scalar(number),
    )
  end

  def placed_item(id, parent_id: nil, placements: nil)
    Sirena::IR::PrepositionedItem.new(
      id: id, parent_id: parent_id,
      placements: placements || [placement("column", 0, 1)]
    )
  end

  context "with ordered items and resolved connectivity" do
    subject(:ir) do
      items = [placed_item("a"), placed_item("b")]
      connection = Sirena::IR::Edge.new(
        id: "a_to_b", source_id: "a", target_id: "b",
      )
      described_class.new(id: "grid", items: items,
                          connections: [connection])
    end

    it "preserves ordered source-domain constraints and connectivity" do
      expect([ir.valid?, ir.items.map(&:id), ir.connections.map(&:id)])
        .to eq([true, %w[a b], ["a_to_b"]])
    end
  end

  it "rejects missing and duplicate placement dimensions" do
    duplicate = [placement("column", 0, 1), placement("column", 1, 2)]
    items = [placed_item("missing", placements: []),
             placed_item("duplicate", placements: duplicate)]

    expect(items.map(&:valid?)).to eq([false, false])
  end

  context "with invalid connectivity" do
    subject(:results) { [duplicate.valid?, dangling.valid?] }

    let(:duplicate) do
      described_class.new(
        id: "grid", items: [placed_item("a"), placed_item("a")],
      )
    end
    let(:dangling) do
      described_class.new(
        id: "grid", items: [placed_item("a")],
        connections: [Sirena::IR::Edge.new(
          id: "edge", source_id: "a", target_id: "missing",
        )]
      )
    end

    it "rejects duplicate identities and dangling endpoints" do
      expect(results).to eq([false, false])
    end
  end

  context "with invalid containment" do
    subject(:results) { [unresolved.valid?, cycle.valid?] }

    let(:unresolved) do
      described_class.new(
        id: "grid", items: [placed_item("a", parent_id: "missing")],
      )
    end
    let(:cycle) do
      described_class.new(
        id: "grid",
        items: [placed_item("a", parent_id: "b"),
                placed_item("b", parent_id: "a")],
      )
    end

    it "rejects unresolved and cyclic containment" do
      expect(results).to eq([false, false])
    end
  end

  context "with valid boundary cases" do
    subject(:results) { [empty.valid?, looped.valid?] }

    let(:empty) { described_class.new(id: "empty") }
    let(:looped) do
      described_class.new(
        id: "grid", items: [placed_item("a")],
        connections: [Sirena::IR::Edge.new(
          id: "loop", source_id: "a", target_id: "a",
        )]
      )
    end

    it "allows empty roots and self-loop connectivity" do
      expect(results).to eq([true, true])
    end
  end
end
