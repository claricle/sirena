# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::ErDiagram do
  subject(:attribute) do
    source = "erDiagram\n  E {\n    string a #{keys}\n  }\n"
    described_class.new.parse(source).entities.first.attributes.first
  end

  {
    "PK" => "PK",
    "PK,FK" => "PK,FK",
    "PK, FK" => "PK,FK",
    "FK , UK" => "FK,UK",
    "PK,UK,FK" => "PK,UK,FK",
  }.each do |written, stored|
    context "with keys #{written.inspect}" do
      let(:keys) { written }

      it "stores #{stored.inspect}" do
        expect(attribute.key_type).to eq(stored)
      end
    end
  end

  context "with a comment after several keys" do
    let(:keys) { 'PK, FK "comment"' }

    it "keeps the comment" do
      expect(attribute.note).to eq("comment")
    end
  end

  context "with PK and FK" do
    let(:keys) { "PK, FK" }

    it "answers true to primary_key? and foreign_key?" do
      expect([attribute.primary_key?, attribute.foreign_key?])
        .to eq([true, true])
    end
  end

  context "with keys separated by space alone" do
    let(:keys) { "UK FK" }

    it "is rejected, as mermaid does" do
      expect { attribute }.to raise_error(Sirena::Parser::ParseError)
    end
  end
end
