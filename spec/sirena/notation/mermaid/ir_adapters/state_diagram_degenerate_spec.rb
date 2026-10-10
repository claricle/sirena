# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/state_diagram"

RSpec.describe Sirena::Notation::Mermaid::IRAdapters::StateDiagram do
  let(:diagram) do
    Sirena::Diagram::StateDiagram.new(
      id: "", states: [Sirena::Diagram::StateNode.new(id: "")],
    )
  end
  let(:ir) { described_class.call(diagram) }

  it "falls back to a generic id for an empty diagram id" do
    expect(ir.id).to eq("item")
  end

  it "numbers a state that arrives without an id" do
    expect(ir.nodes.first.id).to eq("state_0")
  end

  context "when the model carries accessibility readers" do
    before do
      diagram.define_singleton_method(:acc_title) { nil }
      diagram.define_singleton_method(:acc_description) { "Described" }
    end

    it "skips a nil reader and takes the next non-nil one" do
      expect([ir.accessibility_title, ir.accessibility_description])
        .to eq([nil, "Described"])
    end
  end
end
