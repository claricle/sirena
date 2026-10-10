# frozen_string_literal: true

require "spec_helper"
require "sirena/diagram/sequence"

RSpec.describe Sirena::Diagram::Sequence do
  it "accepts an empty sequence as a renderable diagram" do
    sequence = described_class.new

    expect([sequence.valid?, sequence.diagram_type]).to eq([true, :sequence])
  end

  describe Sirena::Diagram::SequenceMessage do
    it "does not mark an ordinary target message as bidirectional" do
      message = described_class.new(from_id: "A", to_id: "B")

      expect(message.bidirectional?).to be(false)
    end

    it "allows an empty message label without weakening endpoint validation" do
      message = described_class.new(
        from_id: "A", to_id: "B", message_text: "",
      )
      expect(message).to be_valid
    end
  end
end
