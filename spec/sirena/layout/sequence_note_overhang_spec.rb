# frozen_string_literal: true

require "spec_helper"

# mmdc lets a note left of the first actor stick out past the left margin
# and grows the canvas leftwards (reference case 009: viewBox "-150 -10
# 350 220", note x -100, actor x 0).
RSpec.describe Sirena::Layout::Sequence do
  include SequenceFrameHelpers

  let(:scene) do
    layout_scene("participant Alice\nNote left of Alice: Alice thinks")
  end

  it "grows the canvas by the part of the note outside the margin" do
    expect(scene.width).to eq(350)
  end

  it "moves the actor right by the same amount" do
    expect(actor_xs(scene)).to eq([150])
  end

  it "puts the note 100 left of the actor box, as mmdc does" do
    expect(scene.notes.first.x).to eq(scene.participants.first.x - 100)
  end

  it "does not shift when the note fits inside the margin" do
    xs = actor_xs(layout_scene("A->>B: x\nNote left of B: hi"))

    expect(xs).to eq([50, 250])
  end
end
