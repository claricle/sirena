# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Diagram::ClassDiagram do
  let(:entity) { Sirena::Diagram::ClassEntity.new(stereotype: "enum") }
  let(:relationships) do
    %w[association dependency realization].map do |type|
      Sirena::Diagram::ClassRelationship.new(relationship_type: type)
    end
  end

  it "identifies the remaining public class diagram kinds" do
    evidence = [entity.enum?] + relationships.map do |relationship|
      relationship.public_send("#{relationship.relationship_type}?")
    end

    expect(evidence).to eq([true, true, true, true])
  end
end
