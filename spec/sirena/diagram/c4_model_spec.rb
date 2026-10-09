# frozen_string_literal: true

require "spec_helper"
require "sirena/diagram/c4"

RSpec.describe Sirena::Diagram::C4 do
  def element(id, **attrs)
    Sirena::Diagram::C4Element.new(id: id, label: id.upcase,
                                   element_type: "System", **attrs)
  end

  def relationship(from, to, **attrs)
    Sirena::Diagram::C4Relationship.new(from_id: from, to_id: to, **attrs)
  end

  let(:boundary_class) { Sirena::Diagram::C4Boundary }
  let(:diagram) do
    described_class.new(
      elements: [element("a"), element("b", boundary_id: "bd")],
      relationships: [relationship("a", "b"),
                      relationship("b", "a", rel_type: "BiRel")],
      boundaries: [
        boundary_class.new(id: "bd", label: "BD",
                           boundary_type: "System_Boundary"),
        boundary_class.new(id: "in", label: "In", parent_id: "bd"),
      ],
    )
  end

  describe "#valid?" do
    it "accepts a consistent diagram" do
      expect(diagram.valid?).to be(true)
    end

    it "rejects an unknown level" do
      diagram.level = "Code"
      expect(diagram.valid?).to be(false)
    end

    context "with an invalid element, relationship or boundary" do
      let(:bad_element) do
        described_class.new(elements: [element("a", label: "")])
      end
      let(:bad_relationship) do
        described_class.new(elements: [element("a")],
                            relationships: [relationship("a", "")])
      end
      let(:bad_boundary) do
        described_class.new(boundaries: [boundary_class.new(id: "x",
                                                            label: "")])
      end

      it "rejects an invalid element, relationship or boundary" do
        bad = [bad_element, bad_relationship, bad_boundary]
        expect(bad.map(&:valid?)).to eq([false, false, false])
      end
    end

    context "with a relationship pointing at a missing endpoint" do
      let(:missing_to) do
        described_class.new(elements: [element("a")],
                            relationships: [relationship("a", "zz")])
      end
      let(:missing_from) do
        described_class.new(elements: [element("a")],
                            relationships: [relationship("zz", "a")])
      end

      it "rejects a relationship that points at a missing source or target" do
        expect([missing_to.valid?, missing_from.valid?]).to eq([false, false])
      end
    end
  end

  describe "element types" do
    let(:ext_person) do
      element("a", external: true).tap { |e| e.element_type = "Person_Ext" }
    end
    let(:untyped) { Sirena::Diagram::C4Element.new(id: "a", label: "A") }

    it "strips the _Ext suffix for the base type and keeps a missing type nil",
       :aggregate_failures do
      expect(ext_person.base_type).to eq("Person")
      expect(untyped.base_type).to be_nil
    end

    it "is invalid without an element type" do
      expect(untyped.valid?).to be(false)
    end
  end

  describe "boundaries and relationships" do
    let(:rel_kinds) do
      diagram.relationships.map { |r| [r.rel_type, r.bidirectional?] }
    end

    it "defaults boundary type, and recognises boundary kinds",
       :aggregate_failures do
      expect(diagram.boundaries.last.boundary_type).to eq("Boundary")
      expect(diagram.boundaries.first.system?).to be(true)
      expect(diagram.boundaries.first.enterprise?).to be(false)
    end

    it "defaults relationship type and recognises bidirectional ones" do
      expect(rel_kinds).to eq([["Rel", false], ["BiRel", true]])
    end

    it "finds elements and boundaries by id", :aggregate_failures do
      expect(diagram.find_element("b").boundary_id).to eq("bd")
      expect(diagram.find_boundary("in").parent_id).to eq("bd")
      expect(diagram.find_element("zz")).to be_nil
    end

    it "lists relationships and members by id", :aggregate_failures do
      expect(diagram.relationships_from("a").map(&:to_id)).to eq(["b"])
      expect(diagram.relationships_to("a").map(&:from_id)).to eq(["b"])
      expect(diagram.elements_in_boundary("bd").map(&:id)).to eq(["b"])
      expect(diagram.boundaries_in_boundary("bd").map(&:id)).to eq(["in"])
    end
  end

  it "defaults the level to Context and reports its diagram type" do
    expect([described_class.new.level,
            described_class.new.diagram_type]).to eq(["Context", :c4])
  end
end
