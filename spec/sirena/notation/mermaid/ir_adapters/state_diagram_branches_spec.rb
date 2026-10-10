# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/state_diagram"

RSpec.describe Sirena::Notation::Mermaid::IRAdapters::StateDiagram do
  subject(:ir) { described_class.call(diagram) }

  let(:diagram) do
    diagram = Sirena::Diagram::StateDiagram.new(
      id: "", states: [Sirena::Diagram::StateNode.new(id: "")],
    )
    diagram.define_singleton_method(:acc_title) { nil }
    diagram.define_singleton_method(:acc_description) { nil }
    diagram.define_singleton_method(:acc_descr) { "Fallback description" }
    diagram
  end

  it "normalizes blank identities and falls back across accessibility fields" do
    state = ir.nodes.find { |node| node.role == "state" }

    expect([ir.valid?, ir.id, state.id, ir.accessibility_title,
            ir.accessibility_description])
      .to eq([true, "item", "state_0", nil, "Fallback description"])
  end
end
