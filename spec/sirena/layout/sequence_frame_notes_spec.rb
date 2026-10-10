# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Sequence do
  include SequenceFrameHelpers
  include SequenceFrameSvgHelpers

  let(:looped) do
    layout_scene("Note over A: pre\nloop L\nA->>B: first\n" \
                 "Note over A,B: inside\nA->>B: second\n" \
                 "Note right of B: last\nend\nNote over B: post\n" \
                 "A->>B: after")
  end
  let(:frame) { looped.frames.first }
  let(:notes) { looped.notes }

  it "encloses a note written in the middle of a loop" do
    expect(encloses?(box_of(frame), box_of(notes[1]))).to be(true)
  end

  it "encloses a note written just before the loop ends" do
    expect(encloses?(box_of(frame), box_of(notes[2]))).to be(true)
  end

  it "keeps a note written before the loop above its outline" do
    expect(bottom_of(notes[0])).to be < frame.y
  end

  it "keeps a note written after the loop below its outline" do
    expect(notes[3].y).to be > bottom_of(frame)
  end

  it "puts the message after the loop below the outline" do
    expect(message_rows(looped).last).to be > bottom_of(frame)
  end

  it "puts the message after the loop below the last note" do
    expect(message_rows(looped).last).to be > bottom_of(notes[3])
  end

  it "keeps a note after an else divider below the divider" do
    scene = layout_scene("alt X\nA->>B: m\nelse Y\nNote over A: late\n" \
                         "A->>B: n\nend")

    expect(scene.notes.first.y).to be > scene.frames.first.dividers.first.y
  end

  it "pushes the messages below a note that sits in a loop" do
    plain = layout_scene("loop L\nA->>B: m\nend\nA->>B: after")

    expect(message_rows(looped).last).to be > message_rows(plain).last
  end
end
