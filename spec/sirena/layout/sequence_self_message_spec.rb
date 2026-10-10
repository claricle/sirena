# frozen_string_literal: true

require "spec_helper"

# Numbers are what local mmdc drew for the same sources, moved to Sirena's
# origin (mmdc's y plus 10). mmdc leaves 30 below a message to itself, and
# 30 more when a frame ends right after it.
RSpec.describe Sirena::Layout::Sequence do
  include SequenceFrameHelpers

  let(:plain) { layout_scene("A->>B: x\nA->>A: hi\nB->>A: y") }
  let(:framed) do
    layout_scene("A->>B: x\nloop L\nB->>B: hi\nend\nB->>A: y")
  end

  it "pushes the row after a message to itself down 30" do
    expect(plain.messages.last.shaft.y1).to eq(237)
  end

  it "grows the canvas by the 30 below a self message" do
    expect(plain.height).to eq(333)
  end

  it "keeps the self message's own row where it was" do
    expect(plain.messages[1].label.y).to eq(153)
  end

  it "pushes the row after a frame that ends on a self message 60" do
    expect(framed.messages.last.shaft.y1).to eq(322)
  end

  it "ends the frame 30 below the self message's own drop" do
    expect(bottom_of(framed.frames.first)).to eq(278)
  end

  it "grows the canvas by 60 when a frame ends on a self message" do
    expect(framed.height).to eq(418)
  end

  it "adds the second 30 once for nested frames ending together" do
    nested = layout_scene("A->>B: x\nloop L\nloop M\nB->>B: a\nend\nend\n" \
                          "B->>A: y")

    expect(nested.messages.last.shaft.y1).to eq(377)
  end

  it "adds nothing extra when the self message ends a section" do
    split = layout_scene("A->>B: x\nalt L\nB->>B: a\nelse M\nB->>A: b\n" \
                         "end\nB->>A: y")

    expect(split.messages.last.shaft.y1).to eq(381)
  end
end
