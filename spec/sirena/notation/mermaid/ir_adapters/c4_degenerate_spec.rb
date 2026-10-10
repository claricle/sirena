# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/c4"

RSpec.describe Sirena::Notation::Mermaid::IRAdapters::C4 do
  let(:diagram) do
    Sirena::Diagram::C4.new(
      id: "", elements: [Sirena::Diagram::C4Element.new(id: "")],
    )
  end
  let(:ir) { described_class.call(diagram) }

  it "falls back to a generic id for an empty diagram id" do
    expect(ir.id).to eq("item")
  end

  it "numbers an element that arrives without an id" do
    expect(ir.nodes.first.id).to eq("element_0")
  end
end
