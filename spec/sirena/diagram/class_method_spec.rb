# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Diagram::ClassMethod do
  # [visibility, symbol]
  symbols = [
    %w[public +], %w[private -], %w[protected #], %w[package ~],
    %w[internal +]
  ]

  symbols.each do |visibility, symbol|
    it "marks #{visibility} visibility with #{symbol}" do
      method = described_class.new(name: "run", visibility: visibility)
      expect(method.visibility_symbol).to eq(symbol)
    end
  end

  # [attributes, row drawn when no source text was kept]
  rows = [
    [{ name: "run" }, "+ run"],
    [{ name: "run", parameters: "a: int" }, "+ run(a: int)"],
    [{ name: "run", return_type: "void" }, "+ run: void"],
    [{ name: "run", parameters: "", return_type: "int", visibility: "-" },
     "+ run(): int"],
  ]

  rows.each do |attributes, row|
    it "draws #{attributes.inspect} as #{row.inspect}" do
      expect(described_class.new(**attributes).display_text).to eq(row)
    end
  end

  it "draws the source head, parameters and return type" do
    method = described_class.new(
      name: "run", text: "+run  (x)", parameters: "x", return_type: "int",
    )
    expect(method.display_text).to eq("+run(x) : int")
  end
end
