# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/sequence"

RSpec.describe Sirena::Notation::Mermaid::IRAdapters::Sequence do
  let(:diagram) do
    Sirena::Diagram::Sequence.new(
      id: "", participants: [Sirena::Diagram::SequenceParticipant.new(id: "")],
    )
  end
  let(:ir) { described_class.call(diagram) }

  it "falls back to a generic id for an empty diagram id" do
    expect(ir.id).to eq("item")
  end

  it "numbers a participant that arrives without an id" do
    expect(ir.nodes.first.id).to eq("participant_0")
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
