# frozen_string_literal: true

require "spec_helper"

# Numbers measured on mmdc output (cases 001 and 003): a message line starts
# one pixel past its source lifeline, towards the target.
RSpec.describe Sirena::Layout::Sequence do
  include SequenceFrameHelpers

  let(:scene) { layout_scene("A->>B: right\nB->>A: left") }

  it "starts a rightward message 1px right of the lifeline" do
    expect(scene.messages.first.shaft.x1)
      .to eq(scene.lifelines.first.x1 + 1)
  end

  it "starts a leftward message 1px left of the lifeline" do
    expect(scene.messages.last.shaft.x1).to eq(scene.lifelines.last.x1 - 1)
  end
end
