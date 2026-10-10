# frozen_string_literal: true

require "spec_helper"

# Expected numbers are mmdc's, read off spec/fixtures_mermaid/sequence
# with the view box origin (-50, -10) moved to (0, 0).
RSpec.describe Sirena::Layout::Sequence do
  include SequenceFrameHelpers

  let(:plain) { layout_scene("A->>B: one\nB->>A: two\nA->>B: three") }
  let(:noted) { layout_scene("A->>B: one\nNote right of B: n\nB->>A: two") }
  let(:looped) { layout_scene("A->>B: one\nloop L\nB->>A: two\nend") }
  let(:after_loop) do
    layout_scene("A->>B: one\nloop L\nB->>A: two\nend\nA->>B: three")
  end
  let(:alted) do
    layout_scene("A->>B: one\nalt X\nB->>A: two\nelse Y\nA->>B: three\nend")
  end

  it "sizes an actor box like mmdc" do
    box = plain.participants.first

    expect([box.width, box.height]).to eq([150, 65])
  end

  it "starts the actors at the diagram margins" do
    box = plain.participants.first

    expect([box.x, box.y]).to eq([50, 10])
  end

  it "puts the first message one pitch below the actor box" do
    expect(message_rows(plain).first).to eq(119)
  end

  it "spaces message rows 44 apart" do
    expect(message_rows(plain)).to eq([119, 163, 207])
  end

  it "drops a note 10 below the message it follows" do
    expect(noted.notes.first.y).to eq(129)
  end

  it "sizes a one-line note like mmdc" do
    expect(noted.notes.first.height).to eq(39)
  end

  it "restarts the pitch from the bottom of a note" do
    expect(message_rows(noted).last).to eq(212)
  end

  it "ends the lifeline 20 below the last message" do
    expect(plain.lifelines.first.y2).to eq(227)
  end

  it "sizes the canvas to the lifeline plus the bottom margins" do
    expect(plain.height).to eq(215 + 44 * 2)
  end

  it "opens a loop 10 below the message before it" do
    expect(looped.frames.first.y).to eq(129)
  end

  it "closes a loop 10 below its last message" do
    frame = looped.frames.first

    expect(frame.y + frame.height).to eq(message_rows(looped).last + 10)
  end

  it "puts an alt divider 15 below the message before it" do
    expect(alted.frames.first.dividers.first.y).to eq(message_rows(alted)[1] + 15)
  end

  it "puts the first row of a loop 89 below the message before it" do
    expect(message_rows(looped)).to eq([119, 208])
  end

  it "restarts the pitch from the bottom of a closed loop" do
    frame = after_loop.frames.first

    expect(message_rows(after_loop).last).to eq(frame.y + frame.height + 44)
  end

  it "puts the next row 74 below an alt divider" do
    expect(message_rows(alted).last - alted.frames.first.dividers.first.y)
      .to eq(74)
  end
end
