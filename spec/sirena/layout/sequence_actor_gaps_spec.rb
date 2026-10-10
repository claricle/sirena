# frozen_string_literal: true

require "spec_helper"

# mmdc widens the gap after an actor so the longest message to its right
# neighbour fits (calculateActorMargins). The text is measured in Arial,
# the font sirena draws in, so widths differ from the reference SVGs.
RSpec.describe Sirena::Layout::Sequence do
  include SequenceFrameHelpers

  let(:long) { "Hello Bob, how are you?" }

  it "keeps the standard gap for a short message" do
    expect(last_actor_x("A->>B: hi")).to eq(250)
  end

  it "widens the gap to fit a long message" do
    expect(last_actor_x("A->>B: #{long}")).to eq(294)
  end

  it "widens it the same for a message sent back" do
    expect(last_actor_x("B->>A: #{long}")).to eq(294)
  end

  it "widens it to the widest line of a <br> message" do
    expect(last_actor_x("A->>B: #{long}<br/>hi")).to eq(294)
  end

  it "does not let a wrapped message pass the actor width" do
    expect(last_actor_x("A->>B: wrap: #{long} #{long}")).to eq(250)
  end

  it "widens the canvas by the same amount" do
    expect(layout_scene("A->>B: #{long}").width).to eq(494)
  end

  it "ignores a message that skips an actor" do
    body = "A->>B: x\nB->>C: y\nA->>C: #{long}"

    expect(actor_xs(layout_scene(body))).to eq([50, 250, 450])
  end

  it "widens the gap after the actor a note sits right of" do
    expect(last_actor_x("A->>B: x\nNote right of A: #{long}")).to eq(294)
  end

  it "widens the gap before the actor a note sits left of" do
    expect(last_actor_x("A->>B: x\nNote left of B: #{long}")).to eq(294)
  end

  it "leaves the gaps alone for a note right of the last actor" do
    expect(last_actor_x("A->>B: x\nNote right of B: #{long}")).to eq(250)
  end

  it "moves every later actor along with a widened gap" do
    body = "A->>B: x\nB->>C: #{long}"

    expect(actor_xs(layout_scene(body))).to eq([50, 250, 494])
  end
end
