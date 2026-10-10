# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Sequence do
  include SequenceFrameHelpers

  it "adds one frame shape per control block" do
    scene = layout_scene("loop a\nopt b\nA->>B: x\nend\nend")

    expect(scene.frames.map(&:kind)).to eq(%w[loop opt])
  end

  it "adds no frame or box shape to a plain diagram" do
    scene = layout_scene("A->>B: x")

    expect([scene.frames, scene.boxes]).to eq([[], []])
  end

  it "grows the canvas to hold the frame rows" do
    framed = layout_scene("loop a\nA->>B: x\nend")

    expect(framed.height).to be > layout_scene("A->>B: x").height
  end

  it "extends the lifelines past the last frame row" do
    scene = layout_scene("loop a\nA->>B: x\nend")
    frame = scene.frames.first

    expect(scene.lifelines.first.y2).to be > frame.y + frame.height
  end

  it "draws a self message inside the frame width" do
    scene = layout_scene("loop a\nA->>A: me\nend")
    frame = scene.frames.first
    loop_x = scene.participants.first

    expect(frame.x + frame.width).to be > loop_x.x + (loop_x.width / 2) + 56
  end

  it "gives an empty frame a height" do
    diagram = parse_sequence("A->>B: x")
    diagram.frames << Sirena::Diagram::SequenceFrame.new(
      kind: "opt", label: "", start_index: 1, end_index: 1, depth: 0,
    )

    expect(described_class.new.call(diagram).frames.first.height).to be > 0
  end

  it "shifts participants down when a box has a title" do
    boxed = layout_scene("box T\nparticipant A\nend\nA->>A: x")

    expect(boxed.participants.first.y).to be > layout_scene("A->>A: x")
      .participants.first.y
  end
end
