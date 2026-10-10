# frozen_string_literal: true

require "spec_helper"

# Boxes and lines are what local mmdc drew for the same sources, moved to
# Sirena's origin (mmdc's y plus 10, x plus 50). mmdc sizes a wrapped note
# before it breaks the text: left of an actor the box is as wide as the
# 150-wide wrapping plus 20, right of one as the wrapping alone, over one
# actor 150, over two actors the span between them plus 50.
RSpec.describe Sirena::Layout::Sequence do
  include SequenceFrameHelpers

  let(:fox) do
    "The quick brown fox jumps over the lazy dog and keeps running " \
      "through the forest until night falls"
  end

  def note_of(placement, text, wrap: "wrap:")
    scene = layout_scene("Alice->>Bob: Hi\nNote #{placement}:#{wrap} #{text}")
    scene.notes.first
  end

  def box(note)
    [note.x, note.y, note.width, note.height]
  end

  it "breaks a note right of an actor at its 150-wide wrapping" do
    expect(note_of("right of Bob", fox).lines.map(&:text)).to eq(
      ["The quick brown", "fox jumps over the", "lazy dog and keeps",
       "running through the", "forest until night", "falls"],
    )
  end

  it "sizes a note right of an actor to its wrapped text" do
    expect(box(note_of("right of Bob", fox))).to eq([350, 129, 150, 134])
  end

  it "widens a note left of an actor by the padding" do
    expect(box(note_of("left of Bob", fox))).to eq([133, 129, 167, 115])
  end

  it "breaks a note left of an actor into five lines" do
    expect(note_of("left of Bob", fox).lines.length).to eq(5)
  end

  it "fits a note over two actors to the span between them" do
    expect(box(note_of("over Alice,Bob", fox))).to eq([100, 129, 250, 77])
  end

  it "breaks a note over two actors at the span less the padding" do
    expect(note_of("over Alice,Bob", fox).lines.map(&:text)).to eq(
      ["The quick brown fox jumps over", "the lazy dog and keeps running",
       "through the forest until night falls"],
    )
  end

  it "gives a note over one actor 150" do
    expect(box(note_of("over Bob", fox))).to eq([250, 129, 150, 134])
  end

  it "leaves a note alone when it does not wrap" do
    expect(note_of("right of Bob", fox, wrap: "").lines.length).to eq(1)
  end

  it "pushes the message after a wrapped note below it" do
    scene = layout_scene("A->>B: x\nNote right of B:wrap: #{fox}\nB->>A: y")

    expect(message_rows(scene).last).to eq(307)
  end

  it "wraps every note under the diagram's wrap setting" do
    scene = mermaid_scene("sequenceDiagram\n%%{wrap}%%\nA->>B: x\n" \
                          "Note over B: #{fox}")

    expect(scene.notes.first.lines.length).to eq(6)
  end

  it "leaves a note that says nowrap: on one line" do
    scene = mermaid_scene("sequenceDiagram\n%%{wrap}%%\nA->>B: x\n" \
                          "Note over B:nowrap: #{fox}")

    expect(scene.notes.first.lines.length).to eq(1)
  end
end
