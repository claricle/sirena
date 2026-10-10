# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Builders::ErDiagram do
  subject(:builder) { described_class.new }

  def entity_statement
    { entity_id: '"A"', attributes: [{ name: "id", key: "unknown" }] }
  end

  def relationship_statement
    {
      from_id: "A", to_id: "B",
      pattern: {
        card_from: { other: "||" }, operator: "--", card_to: "o{"
      },
      label: { label_text: "   " }
    }
  end

  def wrapped_diagram
    builder.apply(
      statements: [entity_statement, relationship_statement, { ignored: true }],
    )
  end

  def fallback_evidence
    diagram = wrapped_diagram
    attribute = diagram.find_entity("A").attributes.first
    relationship = diagram.relationships.first
    [attribute.attribute_type, attribute.key_type,
     relationship.cardinality_from, relationship.cardinality_to,
     relationship.relationship_type, relationship.label]
  end

  def legacy_entity_ids
    diagram = Sirena::Diagram::ErDiagram.new
    builder.send(
      :process_statements, diagram,
      [nil, { entity_id: "ONLY", attributes: nil }]
    )
    builder.send(:process_statement, diagram, nil)
    diagram.entities.map(&:id)
  end

  it "builds the observable fallbacks from a statements wrapper" do
    expect(fallback_evidence)
      .to eq([nil, nil, "one", "zero_or_more", "non-identifying", nil])
  end

  it "ignores non-statement entries in the legacy statement helper" do
    expect(legacy_entity_ids).to eq(["ONLY"])
  end
end
