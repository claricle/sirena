# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Diagram::Architecture do
  describe "#diagram_type" do
    it "returns :architecture" do
      expect(described_class.new.diagram_type).to eq(:architecture)
    end
  end

  describe "#valid?" do
    def group(id, parent_id: nil)
      described_class::Group.new(id: id, label: id, icon: "cloud", parent_id: parent_id)
    end

    def service(id, group_id: nil)
      described_class::Service.new(id: id, label: id, icon: "server", group_id: group_id)
    end

    def junction(id, group_id: nil)
      described_class::Junction.new(id: id, group_id: group_id)
    end

    it "returns true for a diagram with no groups, services, or junctions" do
      expect(described_class.new.valid?).to be true
    end

    it "returns true for a service placed in a declared group" do
      diagram = described_class.new(groups: [group("g")], services: [service("s", group_id: "g")])

      expect(diagram.valid?).to be true
    end

    # group a in b / group b in a — each group is its own ancestor
    # through the other. Real input, not merely a recursion-safety
    # exercise: mermaid's `in <group>` clause has no cycle check upstream,
    # so this reaches the model whether or not either group carries a
    # service of its own.
    it "returns false when two groups are parented to each other" do
      diagram = described_class.new(groups: [group("a", parent_id: "b"), group("b", parent_id: "a")])

      expect(diagram.valid?).to be false
    end

    # A three-group cycle where one member has its own service still
    # counts as a cycle — the direct service only changes whether the
    # broken shape happens to crash downstream, not whether it is valid.
    it "returns false for a three-group cycle even when one member has a direct service" do
      diagram = described_class.new(
        groups: [
          group("a", parent_id: "c"),
          group("b", parent_id: "a"),
          group("c", parent_id: "b"),
        ],
        services: [service("s1", group_id: "a")]
      )

      expect(diagram.valid?).to be false
    end

    it "returns false when a group is its own parent" do
      diagram = described_class.new(groups: [group("a", parent_id: "a")])

      expect(diagram.valid?).to be false
    end

    it "returns false when a group's parent_id names no declared group" do
      diagram = described_class.new(groups: [group("a", parent_id: "nosuchgroup")])

      expect(diagram.valid?).to be false
    end

    it "returns false when a junction's group_id names no declared group" do
      diagram = described_class.new(junctions: [junction("j", group_id: "nosuchgroup")])

      expect(diagram.valid?).to be false
    end

    it "returns false when a service's group_id names no declared group" do
      diagram = described_class.new(services: [service("s", group_id: "nosuchgroup")])

      expect(diagram.valid?).to be false
    end
  end
end
