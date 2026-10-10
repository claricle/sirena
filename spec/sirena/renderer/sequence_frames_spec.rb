# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::Sequence do
  include SequenceFrameHelpers
  include SequenceFrameSvgHelpers

  let(:loop_doc) do
    svg_document("A->>B: before\nloop Every minute\nA->>B: hi\nend\n" \
                 "A->>B: after")
  end

  it "draws a frame outline around the message it wraps" do
    outline = rect_box(svg_group(loop_doc, "frame-0"))
    inside = message_y(loop_doc, 1)

    expect(outline[1]..(outline[1] + outline[3])).to cover(inside)
  end

  it "keeps the message before the frame above it" do
    expect(message_y(loop_doc, 0))
      .to be < rect_box(svg_group(loop_doc, "frame-0"))[1]
  end

  it "keeps the message after the frame below it" do
    top, bottom = rect_box(svg_group(loop_doc, "frame-0")).values_at(1, 3)

    expect(message_y(loop_doc, 2)).to be > top + bottom
  end

  it "draws the keyword and the bracketed title" do
    expect(group_texts(svg_group(loop_doc, "frame-0")))
      .to eq(["loop", "[Every minute]"])
  end

  {
    "opt" => "opt", "break" => "break", "alt" => "alt", "par" => "par",
    "critical" => "critical"
  }.each do |keyword, drawn|
    it "draws a #{keyword} frame with its keyword tab" do
      doc = svg_document("#{keyword} t\nA->>B: x\nend")

      expect(group_texts(svg_group(doc, "frame-0")).first).to eq(drawn)
    end
  end

  it "nests an inner frame inside its outer frame" do
    doc = svg_document("opt a\nloop b\nA->>B: x\nend\nend")
    outer, inner = %w[frame-0 frame-1].map { |id| rect_box(svg_group(doc, id)) }

    expect(encloses?(outer, inner)).to be(true)
  end

  it "makes the outer frame wider than the frame it holds" do
    doc = svg_document("opt a\nloop b\nA->>B: x\nend\nend")
    widths = %w[frame-0 frame-1].map { |id| rect_box(svg_group(doc, id))[2] }

    expect(widths.first).to be > widths.last
  end

  it "draws a dashed divider between the messages of two sections" do
    doc = svg_document("alt ok\nA->>B: x\nelse bad\nA->>B: y\nend")
    line = REXML::XPath.first(svg_group(doc, "frame-0"), ".//line")

    expect(line.attributes["y1"].to_f)
      .to be_between(message_y(doc, 0), message_y(doc, 1))
  end

  it "titles each section with its bracketed label" do
    doc = svg_document("alt ok\nA->>B: x\nelse bad\nA->>B: y\nend")

    expect(group_texts(svg_group(doc, "frame-0"))).to include("[bad]")
  end

  it "fills a rect frame with its colour" do
    doc = svg_document("rect rgb(200,200,255)\nA->>B: x\nend")

    expect(svg_group(doc, "frame-0").elements["rect"].attributes["fill"])
      .to eq("rgb(200,200,255)")
  end

  it "pushes a message below a frame lower than the same message bare" do
    framed = svg_document("loop a\nA->>B: x\nend\nA->>B: y")
    bare = svg_document("A->>B: x\nA->>B: y")

    expect(message_y(framed, 1)).to be > message_y(bare, 1)
  end
end
