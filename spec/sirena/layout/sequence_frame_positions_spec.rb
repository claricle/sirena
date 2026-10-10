# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Sequence do
  include SequenceFrameHelpers

  let(:scene) do
    layout_scene(
      "box Team\nparticipant A\nparticipant B\nend\n" \
      "alt a title that is long enough to wrap onto several lines\n" \
      "A->>B: hi\nelse other\nB->>A: yo\nend",
    )
  end
  let(:frame) { scene.frames.first }

  def svg_texts(id)
    xml = Sirena::Renderer::Sequence.new.render(scene).to_xml
    group = REXML::XPath.first(REXML::Document.new(xml), "//g[@id='#{id}']")
    REXML::XPath.match(group, ".//text").map do |text|
      [text.attributes["x"].to_f, text.attributes["y"].to_f]
    end
  end

  it "publishes a baseline for every title line" do
    expect(frame.title_ys).to eq(
      frame.title_lines.each_index.map { |row| frame.y + 18 + (row * 19) },
    )
  end

  it "publishes the keyword baseline" do
    expect(frame.kind_y).to eq(frame.y + 14)
  end

  it "publishes the divider ends" do
    divider = frame.dividers.first

    expect([divider.x1, divider.x2]).to eq([frame.x, frame.x + frame.width])
  end

  it "serializes the published frame text positions as given" do
    frame.kind_x = 11.0
    frame.title_ys = frame.title_ys.each_index.map { |row| 200.0 + row }

    expect(svg_texts("frame-0").first(1 + frame.title_ys.length))
      .to eq([[11.0, frame.kind_y]] +
             frame.title_ys.map { |y| [frame.title_x, y] })
  end

  it "serializes the published divider text centre as given" do
    frame.dividers.first.text_x = 33.0

    expect(svg_texts("frame-0").last.first).to eq(33.0)
  end

  it "serializes the published box title centre as given" do
    scene.boxes.first.title_x = 44.0

    expect(svg_texts("box-0").first.first).to eq(44.0)
  end
end
