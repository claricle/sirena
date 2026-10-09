# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Diagram do
  describe Sirena::Diagram::ErRelationship do
    def valid_relationship_attributes
      {
        from_id: "customer",
        to_id: "order",
        cardinality_from: "one",
        cardinality_to: "zero_or_more",
      }
    end

    it "defaults to a non-identifying relationship" do
      relationship = described_class.new(**valid_relationship_attributes)

      expect(relationship.relationship_type).to eq("non-identifying")
    end

    required_fields = %i[
      from_id
      to_id
      relationship_type
      cardinality_from
      cardinality_to
    ]

    required_fields.each do |attribute|
      it "rejects an empty #{attribute}" do
        attributes = valid_relationship_attributes.merge(
          relationship_type: "identifying",
          attribute => "",
        )

        expect(described_class.new(**attributes)).not_to be_valid
      end
    end

    it "does not identify an unrelated relationship type" do
      relationship = described_class.new(relationship_type: "association")

      expect(relationship).not_to be_identifying
    end

    it "does not treat an unrelated type as non-identifying" do
      relationship = described_class.new(relationship_type: "association")

      expect(relationship).not_to be_non_identifying
    end
  end

  describe Sirena::Diagram::ErDiagram do
    subject(:diagram) { described_class.new }

    let(:incoming) do
      Sirena::Diagram::ErRelationship.new(from_id: "customer", to_id: "order")
    end
    let(:outgoing) do
      Sirena::Diagram::ErRelationship.new(from_id: "order", to_id: "product")
    end

    before do
      diagram.relationships = [incoming, outgoing]
    end

    it "finds relationships targeting an entity" do
      expect(diagram.relationships_to("order")).to eq([incoming])
    end

    it "returns no incoming relationships for an unrelated entity" do
      expect(diagram.relationships_to("customer")).to be_empty
    end

    it "selects only non-identifying relationships" do
      incoming.relationship_type = "identifying"
      outgoing.relationship_type = "non-identifying"

      expect(diagram.non_identifying_relationships).to eq([outgoing])
    end
  end
end
