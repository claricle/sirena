# frozen_string_literal: true

require "spec_helper"

# mmdc widens the gap after an actor so the longest message to its right
# neighbour fits (calculateActorMargins). The text is measured in Times
# New Roman, as mmdc does: "Hello Bob, how are you?" is 160 wide, which
# gives 250 + 160 + 20 - 150 = 280 (mmdc case 009).
RSpec.describe Sirena::Layout::Sequence do
  include SequenceFrameHelpers

  let(:long) { "Hello Bob, how are you?" }
  let(:twice) { "#{long} #{long}" }
  let(:four_times) { "#{twice} #{twice}" }

  it "keeps the standard gap for a short message" do
    expect(last_actor_x("A->>B: hi")).to eq(250)
  end

  it "widens the gap to fit a long message" do
    expect(last_actor_x("A->>B: #{long}")).to eq(280)
  end

  it "measures a character reference in its encoded form" do
    text = "I #9829; you #infin; times more!"

    expect(last_actor_x("A->>B: #{text}")).to eq(372)
  end

  it "widens it the same for a message sent back" do
    body = "participant A\nparticipant B\nB->>A: #{long}"

    expect(last_actor_x(body)).to eq(280)
  end

  it "widens it to the widest line of a <br> message" do
    expect(last_actor_x("A->>B: #{long}<br/>hi")).to eq(280)
  end

  it "does not let a wrapped message pass the actor width" do
    expect(last_actor_x("A->>B: wrap: #{long} #{long}")).to eq(250)
  end

  it "widens the canvas by the same amount" do
    expect(layout_scene("A->>B: #{long}").width).to eq(480)
  end

  it "gives a self message half its width" do
    body = "participant A\nparticipant B\nA->>A: #{four_times}"

    expect(last_actor_x(body)).to eq(437)
  end

  it "ignores a message that skips an actor" do
    body = "A->>B: x\nB->>C: y\nA->>C: #{long}"

    expect(actor_xs(layout_scene(body))).to eq([50, 250, 450])
  end

  it "widens the gap after the actor a note sits right of" do
    expect(last_actor_x("A->>B: x\nNote right of A: #{long}")).to eq(280)
  end

  it "widens the gap before the actor a note sits left of" do
    expect(last_actor_x("A->>B: x\nNote left of B: #{long}")).to eq(280)
  end

  it "gives half of a note over two actors to the gap before the last" do
    expect(last_actor_x("A->>B: x\nNote over A,B: #{twice}")).to eq(272.5)
  end

  it "gives half of a note over one actor to the gap after it" do
    expect(last_actor_x("A->>B: x\nNote over A: #{four_times}")).to eq(437)
  end

  it "leaves the gaps alone for a note right of the last actor" do
    expect(last_actor_x("A->>B: x\nNote right of B: #{long}")).to eq(250)
  end

  it "moves every later actor along with a widened gap" do
    body = "A->>B: x\nB->>C: #{long}"

    expect(actor_xs(layout_scene(body))).to eq([50, 250, 480])
  end

  describe "with the global wrap setting" do
    let(:head) { "sequenceDiagram\n" }
    let(:message) { "A->>B: #{four_times}" }

    it "caps a message at the wrap width for the bare directive" do
      expect(mermaid_last_x("#{head}%%{wrap}%%\n#{message}")).to eq(250)
    end

    it "caps it for init wrap at the top level" do
      source = %(%%{init: {"wrap": true}}%%\n#{head}#{message})

      expect(mermaid_last_x(source)).to eq(250)
    end

    it "caps it for init wrap under sequence" do
      source = %(%%{init: {"sequence": {"wrap": true}}}%%\n#{head}#{message})

      expect(mermaid_last_x(source)).to eq(250)
    end

    it "leaves a nowrap: message at its full width" do
      source = "#{head}%%{wrap}%%\nA->>B: nowrap: #{long}"

      expect(mermaid_last_x(source)).to eq(280)
    end

    it "does not wrap without the setting" do
      expect(mermaid_last_x("#{head}#{message}")).to be > 400
    end

    it "caps a note too" do
      source = "#{head}%%{wrap}%%\nA->>B: x\nNote right of A: #{four_times}"

      expect(mermaid_last_x(source)).to eq(250)
    end
  end

  describe "the wrap prefix on a note" do
    it "is not drawn for wrap:" do
      expect(note_line_texts("wrap: hi")).to eq(["hi"])
    end

    it "is not drawn for nowrap:" do
      expect(note_line_texts("nowrap: hi")).to eq(["hi"])
    end
  end
end
