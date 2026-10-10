# frozen_string_literal: true

require "spec_helper"

# Numbers are what local mmdc drew, with its y plus 10.
RSpec.describe Sirena::Layout::Sequence do
  include SequenceFrameHelpers

  let(:textless) { layout_scene("A->>B:\nB->>A: g") }
  let(:spaced) { layout_scene("A->>B:   \nB->>A: g") }
  let(:self_loop) { layout_scene("A->>A:\nB->>A: g") }

  it "puts a message with no text 34 higher" do
    expect(textless.messages.map { |m| m.shaft.y1 }).to eq([85, 129])
  end

  it "treats blank text like no text" do
    expect(spaced.messages.first.shaft.y1).to eq(85)
  end

  it "shortens the canvas by the same 34" do
    expect(textless.height).to eq(225)
  end

  it "starts the loop of a self message with no text at the same row" do
    expect(self_loop.messages.first.loop_path).to start_with("M 125,85")
  end
end
