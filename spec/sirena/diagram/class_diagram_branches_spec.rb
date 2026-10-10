# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Diagram::ClassDiagram do
  def entity(id)
    Sirena::Diagram::ClassEntity.new(id: id, name: id)
  end

  def inheritance(from, to)
    Sirena::Diagram::ClassRelationship.new(
      from_id: from, to_id: to, relationship_type: "inheritance",
    )
  end

  def diagram_with(entities, relationships)
    described_class.new(entities: entities, relationships: relationships)
  end

  it "finds inheritance parents and children without including associations" do
    animal, dog, toy = %w[Animal Dog Toy].map { |id| entity(id) }
    relations = [inheritance("Dog", "Animal"), inheritance("Toy", "Toy")]
    diagram = diagram_with([animal, dog, toy], relations)
    expect([diagram.parent_entities("Dog"), diagram.child_entities("Animal")])
      .to eq([[animal], [dog]])
  end

  it "filters incoming relationships independently of outgoing ones" do
    incoming = inheritance("Dog", "Animal")
    outgoing = inheritance("Animal", "Creature")
    diagram = described_class.new(relationships: [incoming, outgoing])
    expect(diagram.relationships_to("Animal")).to eq([incoming])
  end

  describe Sirena::Diagram::ClassAttribute do
    it "builds fallback text with default visibility and an optional type" do
      typed = described_class.new(name: "items", type: "List")
      untyped = described_class.new(name: "count", type: "")

      expect([typed.display_text, untyped.display_text])
        .to eq(["+ items: List", "+ count"])
    end

    it "normalizes source text and removes a classifier suffix" do
      attribute = described_class.new(name: "items", text: "+  items List~T~ *")

      expect(attribute.display_text).to eq("+ items List<T>")
    end
  end
end
