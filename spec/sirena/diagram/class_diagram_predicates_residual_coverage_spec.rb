# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Diagram::ClassDiagram do
  it "identifies the remaining public class diagram kinds" do
    entity = Sirena::Diagram::ClassEntity.new(stereotype: "enum")
    relationships = %w[association dependency realization].map do |type|
      Sirena::Diagram::ClassRelationship.new(relationship_type: type)
    end

    evidence = [entity.enum?] + relationships.map do |relationship|
      relationship.public_send("#{relationship.relationship_type}?")
    end

    expect(evidence).to eq([true, true, true, true])
  end
end
