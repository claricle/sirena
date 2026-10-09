# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::ErDiagram do
  subject(:diagram) { described_class.new.parse(source) }

  let(:ids) { diagram.entities.map(&:id) }

  context "with a hyphenated name" do
    let(:source) { "erDiagram\nPRODUCT ||--o{ ORDER-ITEM : has" }

    it "keeps the hyphen inside one entity" do
      expect(ids).to eq(%w[PRODUCT ORDER-ITEM])
    end

    it "relates the two entities" do
      rel = diagram.relationships.first
      expect([rel.from_id, rel.to_id]).to eq(%w[PRODUCT ORDER-ITEM])
    end
  end

  context "with numeric names" do
    let(:source) do
      "erDiagram\nCUSTOMER ||--o{ 1 : places\n1 ||--|{ u : contains\n1.5\n"
    end

    it "reads integers, decimals and letters as entities" do
      expect(ids).to eq(%w[CUSTOMER 1 u 1.5])
    end
  end

  context "with a quoted name" do
    let(:source) do
      "erDiagram\n\"2.5\" ||--|| ORDER : processes\n\"a b\" {\n  int id\n}\n"
    end

    it "drops the quotes and keeps the text" do
      expect(ids).to eq(["2.5", "ORDER", "a b"])
    end

    it "attaches the attribute block to the quoted entity" do
      entity = diagram.find_entity("a b")
      expect(entity.attributes.map(&:name)).to eq(["id"])
    end
  end

  it "rejects a digit-led word as a relationship end, as mermaid does" do
    expect do
      described_class.new.parse("erDiagram\nA ||--o{ 2abc : x")
    end.to raise_error(Sirena::Parser::ParseError)
  end
end
