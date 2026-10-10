# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Builders::Sequence do
  subject(:builder) { described_class.new }

  let(:ignored_frame_entries) do
    [{ loop_label: "Every minute", loop_statements: ["noise", {}] }, {}]
  end

  let(:captured_participants) do
    [
      { participant: true, id: "A", label: { string: [] } },
      { actor: true, id: "A", label: { string: [] } },
      { participant: true, id: "B", label: { string: " Bee " } },
      { actor: true, id: "B", label: { string: "New Bee" } },
    ]
  end

  let(:participant_details) do
    participants = builder.apply(captured_participants).participants
    builder.send(:update_participant, participants.last, "", "participant")
    participants.map do |item|
      [item.id, item.label, item.actor_type]
    end
  end

  it "ignores non-statement entries inside and outside a frame" do
    frame = builder.apply(ignored_frame_entries).frames.first

    expect(frame)
      .to have_attributes(kind: "loop", label: "Every minute",
                          start_index: 0, end_index: 0)
  end

  it "normalizes captured labels while preserving an existing label" do
    expect(participant_details)
      .to eq([["A", "A", "actor"], ["B", "New Bee", "participant"]])
  end
end
