# frozen_string_literal: true

require "spec_helper"

# Every number is what mmdc drew for the same source (reference cases 020
# and 030, and local mmdc runs of the sources below), moved to Sirena's
# origin: mmdc's y plus 10.
RSpec.describe Sirena::Layout::Sequence do
  include SequenceFrameHelpers

  let(:fox) { "The quick brown fox jumps over the lazy dog" }
  let(:long) do
    "Hello Bob, how are you? If you are not available right now, I can " \
      "leave you a message. Please get back to me as soon as you can!"
  end
  let(:wrapped) do
    mermaid_scene("sequenceDiagram\n%%{wrap}%%\nAlice->>Bob: #{long}\n" \
                  "Note left of Alice: Bob thinks\nBob->>Alice: Fine!")
  end
  let(:broken) do
    layout_scene("A->>B: one<br>two\nNote right of B: n\nA->>B: y")
  end

  def box(shape)
    [shape.x, shape.y, shape.width, shape.height]
  end

  it "draws a wrapped message as the four lines mmdc draws" do
    expect(wrapped.messages.first.label.lines.length).to eq(4)
  end

  it "keeps the first line where a one-line message would put it" do
    expect(wrapped.messages.first.label.y).to eq(109)
  end

  it "puts the last line 19 below the one before, 4 above the arrow" do
    label = wrapped.messages.first.label

    expect(label.y + (3 * label.line_pitch)).to eq(166)
  end

  it "moves the arrow down 17 for every extra line" do
    expect(message_rows(wrapped)).to eq([170, 263])
  end

  it "places the note after a wrapped message below it" do
    expect(box(wrapped.notes.first)).to eq([50, 180, 150, 39])
  end

  it "pushes the rows below a <br> message down by one line" do
    expect(message_rows(broken)).to eq([136, 229])
  end

  it "places a note below a <br> message" do
    expect(box(broken.notes.first)).to eq([350, 146, 150, 39])
  end

  it "grows the canvas by the extra lines" do
    expect(broken.height).to eq(325)
  end

  it "gives a one-line message no drawn lines of its own" do
    expect(wrapped.messages.last.label.lines).to eq([])
  end

  it "grows the row of a self message like any other" do
    one = layout_scene("A->>A: a\nA->>B: x").height
    three = layout_scene("A->>A: a<br>b<br>c\nA->>B: x").height

    expect(three - one).to eq(34)
  end

  it "breaks a message the diagram does not wrap only at a <br>" do
    scene = layout_scene("A->>B: #{long}")

    expect(scene.messages.first.label.lines).to eq([])
  end

  it "does not wrap a message that says nowrap:" do
    scene = mermaid_scene("sequenceDiagram\n%%{wrap}%%\nA->>B:nowrap: #{long}")

    expect(scene.messages.first.label.lines).to eq([])
  end

  describe "a loop around a two-line message" do
    let(:scene) do
      layout_scene("A->>B: x\nloop L\nA->>B: one<br>two\nend\nA->>B: y")
    end

    it "frames the text lines, not just the arrow" do
      expect(box(scene.frames.first)[1..]).to eq([129, 222, 106])
    end

    it "puts the message after it where mmdc does" do
      expect(message_rows(scene)).to eq([119, 225, 279])
    end

    it "grows the canvas to mmdc's height" do
      expect(scene.height).to eq(375)
    end
  end
end
