# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Diagram do
  describe Sirena::Diagram::SequenceParticipant do
    subject(:participant) { described_class.new(id: "A", label: "Alice") }

    let(:invalid_participants) do
      [
        described_class.new(label: "Alice"),
        described_class.new(id: "", label: "Alice"),
        described_class.new(id: "A"),
      ]
    end

    it "defaults to a valid participant" do
      expect([participant.actor_type, participant.valid?])
        .to eq(["participant", true])
    end

    it "rejects a missing or empty id and a missing label" do
      expect(invalid_participants.map(&:valid?)).to eq([false, false, false])
    end
  end

  describe Sirena::Diagram::SequenceMessage do
    subject(:message) { described_class.new(from_id: "A", to_id: "B") }

    let(:invalid_messages) do
      [
        described_class.new(to_id: "B"),
        described_class.new(from_id: "", to_id: "B"),
        described_class.new(from_id: "A"),
        described_class.new(from_id: "A", to_id: ""),
      ]
    end

    it "defaults to a valid filled target message" do
      expect([message.line_style, message.head_style, message.head_side,
              message.valid?]).to eq(["solid", "filled", "target", true])
    end

    it "recognises a bidirectional message" do
      message.head_side = "both"

      expect(message.bidirectional?).to be(true)
    end

    it "rejects missing or empty endpoints" do
      expect(invalid_messages.map(&:valid?)).to eq([false, false, false, false])
    end
  end

  describe Sirena::Diagram::SequenceActivation do
    subject(:activation) do
      described_class.new(participant_id: "A", start_index: 1, end_index: 2)
    end

    let(:invalid_activations) do
      [
        described_class.new(start_index: 1, end_index: 2),
        described_class.new(participant_id: "", start_index: 1, end_index: 2),
        described_class.new(participant_id: "A", end_index: 2),
        described_class.new(participant_id: "A", start_index: 1),
        described_class.new(participant_id: "A", start_index: 2, end_index: 1),
      ]
    end

    it "accepts an ordered activation range" do
      expect(activation.valid?).to be(true)
    end

    it "rejects missing attributes and a reversed range" do
      expect(invalid_activations.map(&:valid?))
        .to eq([false, false, false, false, false])
    end
  end

  describe Sirena::Diagram::SequenceNote do
    subject(:note) do
      described_class.new(text: "", position: "over", participant_ids: ["A"])
    end

    let(:invalid_notes) do
      [
        described_class.new(position: "over", participant_ids: ["A"]),
        described_class.new(text: "note", participant_ids: ["A"]),
        described_class.new(text: "note", position: "over"),
      ]
    end

    it "accepts an empty label and participant ids" do
      expect([note.valid?, note.participant_ids]).to eq([true, ["A"]])
    end

    it "defaults participant ids to an empty collection" do
      expect(described_class.new.participant_ids).to eq([])
    end

    it "rejects a missing label, position, or participant" do
      expect(invalid_notes.map(&:valid?)).to eq([false, false, false])
    end
  end

  describe Sirena::Diagram::Sequence do
    subject(:diagram) do
      described_class.new(
        participants: [alice, bob], messages: [message],
        activations: [activation], notes: [note]
      )
    end

    let(:alice) do
      Sirena::Diagram::SequenceParticipant.new(id: "A", label: "Alice")
    end
    let(:bob) do
      Sirena::Diagram::SequenceParticipant.new(id: "B", label: "Bob")
    end
    let(:message) do
      Sirena::Diagram::SequenceMessage.new(from_id: "A", to_id: "B")
    end
    let(:activation) do
      Sirena::Diagram::SequenceActivation.new(
        participant_id: "A", start_index: 0, end_index: 1,
      )
    end
    let(:note) do
      Sirena::Diagram::SequenceNote.new(
        text: "note", position: "over", participant_ids: ["A", "B"],
      )
    end

    describe "#valid?" do
      it "accepts a consistent sequence" do
        expect(diagram.valid?).to be(true)
      end

      it "rejects a missing participant collection" do
        diagram.participants = nil

        expect(diagram.valid?).to be(false)
      end

      it "rejects an invalid participant" do
        alice.id = ""

        expect(diagram.valid?).to be(false)
      end

      it "rejects an invalid message" do
        message.from_id = ""

        expect(diagram.valid?).to be(false)
      end

      it "rejects an invalid activation" do
        activation.end_index = -1

        expect(diagram.valid?).to be(false)
      end

      it "rejects an invalid note" do
        note.text = nil

        expect(diagram.valid?).to be(false)
      end

      it "accepts a missing message collection" do
        diagram.messages = nil

        expect(diagram.valid?).to be(true)
      end

      it "rejects a message with an unknown source" do
        message.from_id = "missing"

        expect(diagram.valid?).to be(false)
      end

      it "rejects a message with an unknown target" do
        message.to_id = "missing"

        expect(diagram.valid?).to be(false)
      end

      it "accepts a missing activation collection" do
        diagram.activations = nil

        expect(diagram.valid?).to be(true)
      end

      it "rejects an activation for an unknown participant" do
        activation.participant_id = "missing"

        expect(diagram.valid?).to be(false)
      end

      it "accepts a missing note collection" do
        diagram.notes = nil

        expect(diagram.valid?).to be(true)
      end

      it "rejects a note for any unknown participant" do
        note.participant_ids = ["A", "missing"]

        expect(diagram.valid?).to be(false)
      end
    end

    describe "query helpers" do
      it "reports its type and finds participants" do
        expect([diagram.diagram_type, diagram.find_participant("A"),
                diagram.find_participant("missing")]).to eq([:sequence, alice, nil])
      end

      it "filters messages by source and target" do
        expect([diagram.messages_from("A"), diagram.messages_from("B"),
                diagram.messages_to("B"), diagram.messages_to("A")])
          .to eq([[message], [], [message], []])
      end

      it "filters activations by participant" do
        expect([diagram.activations_for("A"), diagram.activations_for("B")])
          .to eq([[activation], []])
      end
    end

    it "defaults every collection to empty" do
      empty = described_class.new

      expect([empty.participants, empty.messages, empty.activations, empty.notes])
        .to eq([[], [], [], []])
    end
  end
end
