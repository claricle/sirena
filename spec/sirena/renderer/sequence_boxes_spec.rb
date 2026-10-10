# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::Sequence do
  include SequenceFrameHelpers
  include SequenceFrameSvgHelpers

  let(:doc) do
    svg_document("participant Z\nbox Aqua Group1\nparticipant A\n" \
                 "participant B\nend\nparticipant C\nA->>B: hi")
  end

  it "draws the box around the participants declared inside it" do
    box = rect_box(svg_group(doc, "box-0"))

    members = participant_boxes(doc, %w[A B])

    expect(members.all? { |m| encloses?(box, m) }).to be(true)
  end

  it "leaves a participant declared before the box outside it" do
    box = rect_box(svg_group(doc, "box-0"))

    expect(encloses?(box, participant_boxes(doc, ["Z"]).first)).to be(false)
  end

  it "leaves a participant declared after the box outside it" do
    box = rect_box(svg_group(doc, "box-0"))

    expect(encloses?(box, participant_boxes(doc, ["C"]).first)).to be(false)
  end

  it "draws the box title" do
    expect(group_texts(svg_group(doc, "box-0"))).to eq(["Group1"])
  end

  it "fills the box with its colour" do
    fill = svg_group(doc, "box-0").elements["rect"].attributes["fill"]

    expect(fill).to eq("Aqua")
  end

  it "draws the box before the participants so it sits behind them" do
    order = REXML::XPath.match(doc, "//*[@id]").map { |n| n.attributes["id"] }

    expect(order.index("box-0")).to be < order.index("participant-A")
  end

  it "keeps the title clear of the participant row" do
    title_y = REXML::XPath.first(svg_group(doc, "box-0"), ".//text")
    participant_top = participant_boxes(doc, ["A"]).first[1]

    expect(title_y.attributes["y"].to_f).to be < participant_top
  end

  it "leaves a gap between two neighbouring boxes" do
    two = svg_document("box a\nparticipant A\nend\nbox b\nparticipant B\nend")
    first, second = %w[box-0 box-1].map { |id| rect_box(svg_group(two, id)) }

    expect(first[0] + first[2]).to be < second[0]
  end
end
