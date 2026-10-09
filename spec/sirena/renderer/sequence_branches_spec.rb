# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::Sequence do
  let(:line_class) { Sirena::Layout::Sequence::Line }
  let(:label_class) { Sirena::Layout::Sequence::Label }
  let(:head_class) { Sirena::Layout::Sequence::Head }

  def line(x1, y1, x2, y2)
    Sirena::Layout::Sequence::Line.new(x1: x1, y1: y1, x2: x2, y2: y2)
  end

  def label(text, x, y, font_size)
    Sirena::Layout::Sequence::Label.new(
      text: text, width: 20, height: 10, x: x, y: y,
      font_size: font_size
    )
  end

  def box(label: nil)
    Sirena::Layout::Sequence::Participant.new(
      id: "box", actor_type: "participant", x: 20, y: 20,
      width: 120, height: 40, corner_radius: 5, label: label
    )
  end

  def actor
    Sirena::Layout::Sequence::Participant.new(
      id: "actor", actor_type: "actor", x: 170, y: 20,
      width: 120, height: 40, corner_radius: 5,
      actor_head: Sirena::Layout::Sequence::Circle.new(
        x: 230, y: 30, radius: 8,
      ),
      actor_lines: [line(230, 38, 230, 55), line(220, 45, 240, 45)]
    )
  end

  def scene(messages)
    Sirena::Layout::Sequence::Scene.new(
      id: "sequence", width: 360, height: 240,
      view_box: "0 0 360 240",
      participants: [box(label: label("Box", 80, 40, 14.0)), box, actor],
      lifelines: [line(80, 60, 80, 200)], messages: messages
    )
  end

  it "renders actor and box variants with and without labels" do
    xml = described_class.new.render(scene([])).to_xml

    expect(xml.scan("<rect").size).to eq(2)
    expect(xml.scan("<circle").size).to eq(1)
    expect(xml).to include('id="participant-actor"', ">Box</text>")
    expect(xml.scan("stroke-dasharray=\"5,5\"").size).to eq(1)
  end

  it "renders dotted shafts, self-loops, polygon and line heads" do
    polygon = head_class.new(shape: "polygon", points: "220,100 212,96 212,104")
    open_head = head_class.new(shape: "open", lines: [line(220, 120, 212, 116)])
    messages = [
      Sirena::Layout::Sequence::Message.new(
        id: "shaft", line_style: "dotted", shaft: line(80, 100, 220, 100),
        heads: [polygon, open_head], label: label("hello", 150, 90, 12.5)
      ),
      Sirena::Layout::Sequence::Message.new(
        id: "loop", line_style: "dotted",
        loop_path: "M 80 140 C 136 140 136 160 80 160", heads: []
      ),
    ]
    xml = described_class.new.render(scene(messages)).to_xml

    expect(xml).to include('id="shaft"', 'id="loop"')
    expect(xml).to include('points="220,100 212,96 212,104"')
    expect(xml.scan("stroke-dasharray=\"5,5\"").size).to eq(3)
    expect(xml).to include('font-size="12.5"')
  end

  it "formats integral and fractional coordinates without losing precision" do
    message = Sirena::Layout::Sequence::Message.new(
      id: "numbers", line_style: "solid", shaft: line(1, 2.5, 3, 4.25),
      heads: [], label: label("n", 2, 3.5, 12.0)
    )
    xml = described_class.new.render(scene([message])).to_xml

    expect(xml).to include('font-size="12"')
    expect(xml).to include('x1="1.0"', 'y1="2.5"', 'x2="3.0"', 'y2="4.25"')
  end
end
