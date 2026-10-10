# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Diagram::ErDiagram do
  def relationship(from, to, type)
    Sirena::Diagram::ErRelationship.new(
      from_id: from, to_id: to, relationship_type: type,
      cardinality_from: "one", cardinality_to: "zero_or_more"
    )
  end

  it "filters incoming relationships independently of outgoing ones" do
    incoming = relationship("CUSTOMER", "ORDER", "identifying")
    outgoing = relationship("ORDER", "ITEM", "non-identifying")
    diagram = described_class.new(relationships: [incoming, outgoing])
    expect(diagram.relationships_to("ORDER")).to eq([incoming])
  end

  it "selects non-identifying relationships" do
    identifying = relationship("A", "B", "identifying")
    non_identifying = relationship("B", "C", "non-identifying")
    diagram = described_class.new(relationships: [identifying, non_identifying])
    expect(diagram.non_identifying_relationships).to eq([non_identifying])
  end

  it "accepts an explicitly absent relationship collection" do
    entity = Sirena::Diagram::ErEntity.new(id: "CUSTOMER", name: "CUSTOMER")
    diagram = described_class.new(entities: [entity], relationships: nil)

    expect(diagram).to be_valid
  end
end
