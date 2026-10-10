# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Timeline do
  include TimelineSceneHelpers

  subject(:layout) { described_class.new }

  let(:untimed) do
    diagram = Sirena::Diagram::Timeline.new
    diagram.events.push(
      Sirena::Diagram::TimelineEvent.new(time: "Now", descriptions: [" a "]),
      Sirena::Diagram::TimelineEvent.new(time: nil, descriptions: ["b"]),
    )
    layout.call(diagram)
  end
  let(:quiet) do
    diagram = Sirena::Diagram::Timeline.new
    diagram.sections << Sirena::Diagram::TimelineSection.new("Quiet")
    layout.call(diagram)
  end

  # mmdc 016_spec_diagram-orchestration_spec_15: viewBox 100 50 400 100
  it "draws only the base arrow for an empty timeline" do
    scene = layout.call(Sirena::Diagram::Timeline.new)

    expect([scene.width, scene.height, scene.cards]).to eq([400, 100, []])
  end

  it "trims the text of a standalone event" do
    expect(cards_of(untimed, "event").map(&:lines)).to eq([["a"], ["b"]])
  end

  it "gives a period without a time no text" do
    expect(cards_of(untimed, "period").map(&:lines)).to eq([["Now"], []])
  end

  it "draws an empty section as one card without periods" do
    expect(quiet.cards.map(&:kind)).to eq(["section"])
  end

  it "gives an empty section the width of one column" do
    expect(box(quiet.cards.first)).to eq([100, 50, 190, 67.8])
  end
end
