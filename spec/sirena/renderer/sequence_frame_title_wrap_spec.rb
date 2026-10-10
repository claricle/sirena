# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::Sequence do
  include SequenceFrameHelpers
  include SequenceFrameSvgHelpers

  let(:doc) do
    svg_document("Service-->DB: connect\ncritical Establish a connection " \
                 "to the DB\nService-->DB: x\nend")
  end
  let(:titles) do
    REXML::XPath.match(svg_group(doc, "frame-0"), ".//*[local-name()='text']")
      .reject { |node| node.text == "critical" }
  end

  it "draws a wrapped title as one text per line" do
    expect(titles.map(&:text)).to eq(["[Establish a connection", "to the DB]"])
  end

  it "sets the lines 19px apart" do
    ys = titles.map { |node| node.attributes["y"].to_f }

    expect(ys.each_cons(2).map { |a, b| b - a }).to eq([19.0])
  end
end
