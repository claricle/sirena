# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::TimelineFlow do
  include TimelineSceneHelpers

  # Numbers are the ones mmdc draws: 010_..., 013_... and 007_... under
  # spec/fixtures_mermaid/timeline.
  let(:two_sections) do
    [{ name: "abc-123", periods: [period("task1"), period("task2")] },
     { name: "abc-456", periods: [period("task3"), period("task4")] }]
  end
  let(:flow) { described_class.new(two_sections, sectioned: true) }
  let(:plain) do
    groups = [{ name: nil, periods: [period("2002", "LinkedIn"),
                                     period("2004", "Facebook", "Google")] }]
    described_class.new(groups, sectioned: false)
  end

  it "puts a section above its periods, 390 wide for two" do
    expect(box(cards_of(flow, "section").first)).to eq([200, 50, 390, 67.8])
  end

  it "starts the next section after the columns of the last" do
    expect(box(cards_of(flow, "section").last)).to eq([600, 50, 390, 67.8])
  end

  it "puts periods 200 apart under their section" do
    expect(cards_of(flow, "period").map { |card| box(card).first(2) })
      .to eq([[200, 167.8], [400, 167.8], [600, 167.8], [800, 167.8]])
  end

  it "drops a dashed line from the middle of a period" do
    expect(drop_line(cards_of(flow, "period").first))
      .to eq([295, 235.6, 295, 435.6])
  end

  it "puts the base arrow under the period row" do
    expect(flow.axis_y).to be_within(0.001).of(285.6)
  end

  it "numbers the colour of each section's cards from zero" do
    expect(flow.cards.map(&:color_index)).to eq([0, 0, 0, 1, 1, 1])
  end

  it "stacks events 200 under the period, 10 apart" do
    expect(cards_of(plain, "event").map { |card| box(card)[0, 2] })
      .to eq([[200, 250], [400, 250], [400, 310]])
  end

  it "ends the drop line under the tallest event stack" do
    expect(drop_line(cards_of(plain, "period").first))
      .to eq([295, 117.8, 295, 423.4])
  end

  it "draws no section card without sections" do
    expect(cards_of(plain, "section")).to be_empty
  end

  it "puts the base arrow 100 under the tallest period" do
    expect(plain.axis_y).to be_within(0.001).of(167.8)
  end
end
