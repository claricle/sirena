# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Diagram::ErDiagram do
  def er_entity(id)
    Sirena::Diagram::ErEntity.new(id: id, name: id)
  end

  def er_relationship(**attributes)
    defaults = {
      from_id: "CUSTOMER", to_id: "ORDER",
      relationship_type: "non-identifying",
      cardinality_from: "one", cardinality_to: "zero_or_more"
    }
    Sirena::Diagram::ErRelationship.new(**defaults, **attributes)
  end

  def er_diagram(entities: [], relationships: [])
    described_class.new(entities: entities, relationships: relationships)
  end

  def diagram_with_mixed_relationships
    er_diagram(
      relationships: [
        er_relationship(relationship_type: "identifying"),
        er_relationship(
          from_id: "ORDER", to_id: "PRODUCT", cardinality_to: "one_or_more",
        ),
      ],
    )
  end

  describe "#diagram_type" do
    it "returns :er_diagram" do
      diagram = described_class.new
      expect(diagram.diagram_type).to eq(:er_diagram)
    end
  end

  describe "#valid?" do
    it "returns true for valid diagram with entities" do
      diagram = er_diagram(entities: [er_entity("CUSTOMER")])

      expect(diagram.valid?).to be true
    end

    it "returns true for a diagram with no entities" do
      diagram = described_class.new
      expect(diagram.valid?).to be true
    end

    it "returns false when the entity collection is missing" do
      diagram = described_class.new(entities: nil)

      expect(diagram.valid?).to be false
    end

    it "returns false when an embedded entity is invalid" do
      diagram = described_class.new
      diagram.entities << Sirena::Diagram::ErEntity.new(id: "CUSTOMER")

      expect(diagram.valid?).to be false
    end

    it "returns false when an embedded relationship is invalid" do
      diagram = er_diagram(
        entities: %w[CUSTOMER ORDER].map { |id| er_entity(id) },
        relationships: [er_relationship(cardinality_from: nil)],
      )

      expect(diagram.valid?).to be false
    end

    # The valid entity is needed to reach the relationship branch at all.
    it "returns false when a relationship member is nil" do
      diagram = er_diagram(
        entities: [er_entity("CUSTOMER")], relationships: [nil],
      )

      expect(diagram.valid?).to be false
    end

    it "returns false when an entity member is nil" do
      diagram = described_class.new(entities: [nil])

      expect(diagram.valid?).to be false
    end

    it "returns false when an empty diagram has dangling relationships" do
      diagram = er_diagram(relationships: [er_relationship])

      expect(diagram.valid?).to be false
    end

    it "returns false when relationship references non-existent entity" do
      diagram = er_diagram(
        entities: [er_entity("CUSTOMER")],
        relationships: [er_relationship],
      )

      expect(diagram.valid?).to be false
    end
  end

  describe "#find_entity" do
    let(:diagram) { described_class.new }
    let(:entity) do
      Sirena::Diagram::ErEntity.new(
        id: "CUSTOMER",
        name: "CUSTOMER",
      )
    end

    before { diagram.entities << entity }

    it "finds entity by id" do
      expect(diagram.find_entity("CUSTOMER")).to eq(entity)
    end

    it "returns nil for non-existent id" do
      expect(diagram.find_entity("UNKNOWN")).to be_nil
    end
  end

  describe "#relationships_from" do
    let(:diagram) { described_class.new }
    let(:relationship) do
      Sirena::Diagram::ErRelationship.new(
        from_id: "CUSTOMER",
        to_id: "ORDER",
        relationship_type: "non-identifying",
        cardinality_from: "one",
        cardinality_to: "zero_or_more",
      )
    end

    before { diagram.relationships << relationship }

    it "finds relationships originating from entity" do
      expect(diagram.relationships_from("CUSTOMER")).to eq([relationship])
    end

    it "returns empty array for entity with no outgoing relationships" do
      expect(diagram.relationships_from("ORDER")).to eq([])
    end
  end

  describe "#add_class_def" do
    let(:diagram) { described_class.new }

    it "records a single declaration verbatim" do
      diagram.add_class_def("a", "fill:red")

      expect(diagram.class_defs).to eq("a" => "fill:red")
    end

    it "accumulates a repeated declaration for the same name, not replaces it" do
      # Mermaid's own db stores every classDef for one name as an array in
      # source order rather than overwriting; verified against its parser.
      # Comma-joining reproduces that, since parse_declaration already
      # resolves a comma run left to right.
      diagram.add_class_def("a", "fill:red")
      diagram.add_class_def("a", "stroke:blue")

      expect(diagram.class_defs).to eq("a" => "fill:red,stroke:blue")
    end

    it "keeps declarations for different names independent" do
      diagram.add_class_def("a", "fill:red")
      diagram.add_class_def("b", "fill:blue")

      expect(diagram.class_defs).to eq("a" => "fill:red", "b" => "fill:blue")
    end
  end

  describe "#identifying_relationships" do
    let(:diagram) { described_class.new }

    it "returns only identifying relationships" do
      relationships = diagram_with_mixed_relationships.identifying_relationships
      expect(relationships.length).to eq(1)
      expect(relationships.first.relationship_type).to eq("identifying")
    end
  end
end

RSpec.describe Sirena::Diagram::ErEntity do
  def entity_with(attributes)
    described_class.new(
      id: "CUSTOMER", name: "CUSTOMER", attributes: attributes,
    )
  end

  describe "#valid?" do
    it "returns true for entity with id and name" do
      entity = described_class.new(id: "CUSTOMER", name: "CUSTOMER")
      expect(entity.valid?).to be true
    end

    it "returns false for entity without id" do
      entity = described_class.new(name: "CUSTOMER")
      expect(entity.valid?).to be false
    end

    it "returns false for entity without name" do
      entity = described_class.new(id: "CUSTOMER")
      expect(entity.valid?).to be false
    end

    it "returns false when the attribute collection is missing" do
      entity = entity_with(nil)

      expect(entity.valid?).to be false
    end

    it "returns false when an attribute member is nil" do
      entity = entity_with([nil])

      expect(entity.valid?).to be false
    end
  end
end

RSpec.describe Sirena::Diagram::ErAttribute do
  describe "#valid?" do
    it "returns true for attribute with name" do
      attribute = described_class.new(name: "customer_id")
      expect(attribute.valid?).to be true
    end

    it "returns false for attribute without name" do
      attribute = described_class.new
      expect(attribute.valid?).to be false
    end
  end

  describe "#primary_key?" do
    it "returns true when key_type is PK" do
      attribute = described_class.new(
        name: "id",
        key_type: "PK",
      )
      expect(attribute.primary_key?).to be true
    end

    it "returns false when key_type is not PK" do
      attribute = described_class.new(name: "name")
      expect(attribute.primary_key?).to be false
    end
  end

  describe "#foreign_key?" do
    it "returns true when key_type is FK" do
      attribute = described_class.new(
        name: "customer_id",
        key_type: "FK",
      )
      expect(attribute.foreign_key?).to be true
    end

    it "returns false when key_type is not FK" do
      attribute = described_class.new(name: "name")
      expect(attribute.foreign_key?).to be false
    end
  end
end

RSpec.describe Sirena::Diagram::ErRelationship do
  def relationship(**attributes)
    defaults = {
      from_id: "CUSTOMER", to_id: "ORDER",
      relationship_type: "non-identifying",
      cardinality_from: "one", cardinality_to: "zero_or_more"
    }
    described_class.new(**defaults, **attributes)
  end

  describe "#valid?" do
    it "returns true for relationship with all required fields" do
      expect(relationship.valid?).to be true
    end

    it "returns false without from_id" do
      expect(relationship(from_id: nil).valid?).to be false
    end

    it "returns false without cardinality_from" do
      expect(relationship(cardinality_from: nil).valid?).to be false
    end
  end

  describe "#identifying?" do
    it "returns true for identifying type" do
      identifying = relationship(relationship_type: "identifying")
      expect(identifying.identifying?).to be true
    end

    it "returns false for other types" do
      expect(relationship.identifying?).to be false
    end
  end

  describe "#non_identifying?" do
    it "returns true for non-identifying type" do
      expect(relationship.non_identifying?).to be true
    end
  end
end
