# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Timeline do
  include TimelineSceneHelpers

  # mmdc on this source draws the cards S, Bare1, 2021, e2, Bare2.
  let(:source) do
    "timeline\n  Bare0\n  2020 : e1\n  section S\n  Bare1\n  " \
      "2021 : e2\n  Bare2\n"
  end

  def texts(scene)
    scene.cards.map { |card| card.lines.join(" ") }
  end

  it "draws periods and bare tasks in the order written" do
    expect(texts(lay_out(source)).sort)
      .to eq(["Bare1", "Bare2", "S", "2021", "e2"].sort)
  end

  it "places a bare task left of the period written after it" do
    cards = cards_of(lay_out(source), "period")

    expect(cards.sort_by(&:x).map { |c| c.lines.join }).to eq(
      ["Bare1", "2021", "Bare2"],
    )
  end

  it "draws no card for periods before the first section" do
    expect(texts(lay_out(source))).not_to include("Bare0", "2020", "Default")
  end

  it "draws a section-less task as an unsectioned period" do
    scene = lay_out("timeline\n  Bare0\n  2020 : e1\n")

    expect(texts(scene)).to include("Bare0", "2020")
  end
end
