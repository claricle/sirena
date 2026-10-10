# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Diagram::ClassAttribute do
  # [visibility, symbol]
  symbols = [
    %w[public +], %w[private -], %w[protected #], %w[package ~],
    %w[internal +]
  ]

  symbols.each do |visibility, symbol|
    it "marks #{visibility} visibility with #{symbol}" do
      attribute = described_class.new(name: "id", visibility: visibility)
      expect(attribute.visibility_symbol).to eq(symbol)
    end
  end

  # [attributes, row drawn when no source text was kept]
  rows = [
    [{ name: "id" }, "+ id"],
    [{ name: "id", type: "" }, "+ id"],
    [{ name: "id", type: "int", visibility: "private" }, "- id: int"],
  ]

  rows.each do |attributes, row|
    it "draws #{attributes.inspect} as #{row.inspect}" do
      expect(described_class.new(**attributes).display_text).to eq(row)
    end
  end

  it "draws the source text when the parser kept it" do
    attribute = described_class.new(name: "id", text: "+id  int *")
    expect(attribute.display_text).to eq("+id int")
  end
end
