# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Builders::ErDiagram do
  subject(:builder) { described_class.new }

  it "builds the observable fallbacks from a statements wrapper" do
    diagram = builder.apply(
      statements: [
        {
          entity_id: '"A"',
          attributes: [{ name: "id", key: "unknown" }],
        },
        {
          from_id: "A",
          to_id: "B",
          pattern: {
            card_from: { other: "||" },
            operator: "--",
            card_to: "o{",
          },
          label: { label_text: "   " },
        },
        { ignored: true },
      ],
    )

    attribute = diagram.find_entity("A").attributes.first
    relationship = diagram.relationships.first

    expect(attribute.attribute_type).to be_nil
    expect(attribute.key_type).to be_nil
    expect(relationship.cardinality_from).to eq("one")
    expect(relationship.cardinality_to).to eq("zero_or_more")
    expect(relationship.relationship_type).to eq("non-identifying")
    expect(relationship.label).to be_nil
  end

  it "ignores non-statement entries in the legacy statement helper" do
    diagram = Sirena::Diagram::ErDiagram.new

    builder.send(
      :process_statements,
      diagram,
      [nil, { entity_id: "ONLY", attributes: nil }],
    )
    builder.send(:process_statement, diagram, nil)

    expect(diagram.entities.map(&:id)).to eq(["ONLY"])
  end
end
