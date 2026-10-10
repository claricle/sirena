# frozen_string_literal: true

require "spec_helper"

# Numbers measured on mmdc output, view box origin (-50, -10) moved to 0.
RSpec.describe Sirena::Layout::Sequence do
  include SequenceFrameHelpers

  let(:bare) { layout_scene("box green\nparticipant a\nend\na->>a: m") }
  let(:titled) { layout_scene("box green T\nparticipant a\nend\na->>a: m") }
  let(:middle) do
    layout_scene(<<~BODY)
      participant x
      box green T
      participant a
      participant b
      end
      participant c
      box red
      participant d
      end
      x->>c: hi
    BODY
  end

  it "starts a titled box's actors 27px lower than a plain diagram" do
    expect(titled.participants.first.y).to eq(10 + 27)
  end

  it "starts an untitled box's actors 10px lower" do
    expect(bare.participants.first.y).to eq(10 + 10)
  end

  it "leaves 10px under the canvas for any box" do
    plain = layout_scene("participant a\na->>a: m")

    expect(bare.height - plain.height).to eq(20)
  end

  it "draws the box 25px wider than its actors on each side" do
    actor = titled.participants.first
    box = titled.boxes.first

    expect([actor.x - box.x, box.width]).to eq([25, actor.width + 50])
  end

  it "starts the box 5px above the diagram margin" do
    expect(bare.boxes.first.y).to eq(5)
  end

  it "pushes the actor after a box 15px further and one before 5px" do
    expect(middle.participants.map(&:x)).to eq([50, 255, 455, 670, 875])
  end

  it "adds 30px of width for two boxes, one at the end" do
    plain = layout_scene("participant x\nparticipant a\nparticipant b\n" \
                         "participant c\nparticipant d\nx->>c: hi")

    expect(middle.width - plain.width).to eq(30)
  end
end
